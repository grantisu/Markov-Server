use strict;
use warnings;

use Coro;
use Plack::Request;
use String::Markov;

my %info = (
	name   => {
		desc => 'A list of 3000 names',
		order    => 2,
		maxlines => 50,
	},
	raven  => {
		desc => 'Edgar Allen Poe\'s <i>The Raven</i>',
		order    => 3,
		maxlines => 20,
	},
	rime   => {
		desc => 'Samuel Taylor Coleridge\'s <i>Rime of the Ancient Mariner</i>',
		order    => 4,
		maxlines => 20,
	},
	sermon => {
		desc => 'Matthew 5-7 from the King James Bible; Sermon on the Mount',
		order    => 5,
		maxlines => 15,
	},
	rigveda => {
		desc => 'Rig Veda, Book 10, Hymns 1-10',
		order    => 3,
		maxlines => 15,
	},
	utf8 => {
		desc => 'Unicode sample text (https://www.cl.cam.ac.uk/~mgk25/ucs/examples/UTF-8-demo.txt)',
		order    => 2,
		maxlines => 20,
	},
);

sub help_doc {
	my @page = (
	'<html><head><title>Help</title></head><body>',
	'Generate random sequences of characters from the following sources:',
	'<ul>',
	);

	while (my ($k, $v) = each %info) {
		push @page,
		"<li><b>$k</b>: $v->{desc}<br>",
		"Context: $v->{order}; Max lines: $v->{maxlines}",
		"</li>";
	}

	push @page, '</ul></body></html>';

	return \@page;
}


my %fcache;
sub get_flood {
	my ($name) = @_;

	if (!defined $fcache{$name}) {
		my $c = Coro::Channel->new(250);
		my $o = $info{$name}{order} || 2;
		my $mc = String::Markov->new(order => $o, do_chomp => 0);
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
	my $lcount = $req->query_parameters->{l} || 10;
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

	$path = 'name' if !$path;

	if (! -f "$path.txt") {
		my $resp = $req->new_response(404);
		$resp->content_type('text/html');
		$resp->body("<html><h1>404 Not Found</h1>$path</html>");
		return $resp->finalize;
	}

	my $fh = get_flood($path);
	my @lines = map { $fh->get } 1..$lcount;

	return [ 200, ['Content-Type','text/plain; charset=utf-8'], \@lines ];
};

