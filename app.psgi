use strict;
use warnings;

use Coro;
use Plack::Builder;
use Plack::Request;
use String::Markov;

my %info = (
	names  => {
		desc => 'A list of 3000 names',
		order    => 2,
		maxlines => 50,
		as_list  => 1,
	},
	dict   => {
		desc => 'Definitions from <i>The Devil\'s Dictionary</i> by Ambrose Bierce',
		order    => 1,
		maxlines => 10,
		sep      => ' ',
	},
	raven  => {
		desc => 'Edgar Allan Poe\'s <i>The Raven</i>',
		order    => 4,
		maxlines => 20,
	},
	rime   => {
		desc => 'Samuel Taylor Coleridge\'s <i>Rime of the Ancient Mariner</i>',
		order    => 4,
		maxlines => 20,
	},
	sermon => {
		desc => 'Matthew 5-7, <i>Sermon on the Mount</i> (KJV)',
		order    => 5,
		maxlines => 15,
	},
	rigveda => {
		desc => 'Tenth Mandala of the Rigveda, Hymns 1-10',
		order    => 3,
		maxlines => 15,
	},
);

sub help_doc {
	my @page = (
	'<html><head><title>Help</title></head><body>',
	'Use <a href="http://search.cpan.org/~gmathews/String-Markov-0.004/lib/String/Markov.pm">String::Markov<a> to generate random sequences of characters from the following sources:',
	'<ul>',
	);

	while (my ($k, $v) = each %info) {
		push @page,
		"<li><b><a href=\"./$k\">$k</a></b>: $v->{desc}<br>",
		"Order: $v->{order} (${\( $v->{sep} ? 'word' : 'char' )}); Max lines: $v->{maxlines}",
		"</li>";
	}

	push @page, '</ul>Advanced options: try <a href="./names?plain;l=25">./names?plain;l=25</a></body></html>';

	return \@page;
}

sub make_pretty {
	my ($name, $mk_list, $lines) = @_;
	my @page = ("<html><head><title>$name</title></head><body style='max-width: 75em;'><h3>$name</h3>\n");

	if ($mk_list) {
		push @page, "<ul style=\"list-style-type: none;\">\n", (map { "<li>$_</li>\n" } @$lines), "\n</ul>";
	} else {
		push @page, (map { s/_([^_]+)_/<em>\1<\/em>/; /^\s*$/ ? '<br>' : "<p>$_</p>\n" } @$lines);
	}

	push @page, '</body></html>';

	return [ 200, ['Content-Type','text/html; charset=utf-8'], \@page];
}

my %fcache;
sub get_channel {
	my ($name) = @_;

	if (!defined $fcache{$name}) {
		my $c = Coro::Channel->new(500);
		my $o = $info{$name}{order} || 2;
		my $mc = String::Markov->new(order => $o, do_chomp => 0, sep => $info{$name}{sep});
		$mc->add_files("$name.txt");
		async { while (1) { $c->put(scalar($mc->generate_sample)); }; };
		$fcache{$name} = $c;
	}

	return $fcache{$name};
}

my $app = sub {
	my $env = shift;
	my $req = Plack::Request->new($env);
	my $path = $req->path;
	my $qp = $req->query_parameters;

	my $lcount = $qp->{l} || 10;
	$path =~ s|^/||;

	if ($path =~ m|/| || ($info{$path} && $info{$path}{maxlines} < $lcount)) {
		my $resp = $req->new_response(400);
		$resp->content_type('text/html');
		$resp->body("<html><h1>400 Bad Request</h1>$path<br>$lcount</html>");
		return $resp->finalize;
	} elsif ($path eq 'help') {
		my $resp = $req->new_response(200);
		$resp->content_type('text/html');
		$resp->body(help_doc);
		return $resp->finalize;
	}

	$path = 'names' if !$path;

	if (! -f "$path.txt") {
		my $resp = $req->new_response(404);
		$resp->content_type('text/html');
		$resp->body("<html><h1>404 Not Found</h1>$path</html>");
		return $resp->finalize;
	}

	my $ch = get_channel($path);
	my @lines = map { $ch->get } 1..$lcount;

	if (defined $qp->{plain}) {
		return [ 200, ['Content-Type','text/plain; charset=utf-8'], \@lines ];
	} else {
		return make_pretty($path, $info{$path}{as_list}, \@lines);
	}
};


builder {
	mount '/markov' => builder {
		enable_if { $_[0]->{REMOTE_ADDR} eq '127.0.0.1' } 
			"Plack::Middleware::ReverseProxy";
		$app;
	},
};
