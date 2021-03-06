use strict;
use warnings;

use Cache::LRU;
use Coro;
use Plack::Builder;
use Plack::Request;
use String::Markov 0.008;

my %info = (
	names  => {
		desc => 'A list of 3000 names',
		order    => 2,
		maxlines => 25,
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

my $style = <<STYLE;
<meta name="viewport" content="width=device-width">
<style>
html  { padding: 2em; }
body { max-width: 40em; margin: auto; }
li { margin-top: 0.4em; }
.small { font-size: 80%; margin: 2.5em; }
</style>
STYLE

sub index_doc {
	my @page = ( <<HEADER
<html>
<head>
<title>Markov Server</title>
$style
</head>
<body>
<h3>Markov Server</h3>
This is a simple <a href="http://plackperl.org">PSGI</a> application that uses
<a href="http://search.cpan.org/~gmathews/String-Markov/lib/String/Markov.pm">String::Markov</a>
to generate random sequences of characters from the following sources:
<ul>
HEADER
	);

	foreach my $k (sort keys %info) {
		my $v = $info{$k};
		push @page, <<ITEM;
<li>
<b><a href=\"./$k\">$k</a></b>: $v->{desc}<br>
<span class='small'>Order: $v->{order} (${\( $v->{sep} ? 'word' : 'char' )})</span>
</li>
ITEM
	}

	push @page, <<FOOTER;
</ul>
<a class="small" href="http://github.com/grantisu/Markov-Server">source code</a>
<a class="small" href="http://www.gmathews.com/writing/markov_chains.html">explanation</a>
</body>
</html>
FOOTER
	return \@page;
}

sub make_pretty {
	my ($name, $qstr, $mk_list, $lines, $seed) = @_;

	$qstr =~ s/&?seed=[^&]*//;

	my @page = ( <<HEADER
<html>
<head>
<title>$name</title>
$style
</head>
<body>
<h3><a href=\"?$qstr\">$name</a></h3>
HEADER
);

	if ($mk_list) {
		push @page, "<ul style=\"list-style-type: none;\">\n", (map { "<li>\n$_</li>\n" } @$lines), "\n</ul>";
	} else {
		push @page, (map { s/_([^_]+)_/<em>$1<\/em>/g; /^\s*$/ ? '<br>' : "<p>$_</p>\n" } @$lines);
	}

	$qstr .= '&' if $qstr;

	push @page,
		'<a class="small" href=".">Index</a>',
		"<a class=\"small\" href=\"?${qstr}seed=$seed\">permalink</a>",
		"<a class=\"small\" href=\"?${qstr}plain&seed=$seed\">plain</a>",
		'</body></html>';

	return \@page;
}

my $rchan = Coro::Channel->new(100);
async {
	while (1) { $rchan->put(int(rand(2147483648))); }
}

my %fcache;
my $pcache = Cache::LRU->new(size => 500);
my $mcache = Cache::LRU->new(size => 1000);

sub get_chain {
	my ($name) = @_;

	if (!defined $fcache{$name}{chain}) {
		my $o = $info{$name}{order} || 2;
		my $mc = String::Markov->new(order => $o, do_chomp => 0, sep => $info{$name}{sep});
		$mc->add_files("$name.txt");
		$fcache{$name}{chain} = $mc;
	}

	return $fcache{$name}{chain};
}

sub generate_samples {
	my ($name, $rseed) = @_;

	my $l = $info{$name}{maxlines} || 10;
	my $nfix = $info{$name}{sep} ? "\n" : '';
	my $mc = get_chain($name);

	srand($rseed);
	return [ map { $mc->generate_sample . $nfix } 1..$l ];
}

sub get_channel {
	my ($name) = @_;

	if (!defined $fcache{$name}{channel}) {
		my $c = Coro::Channel->new(40);
		async {
			while (1) {
				my $rseed = $rchan->get;
				my $results = generate_samples($name, $rseed);
				$c->put([$rseed, $results]);
			};
		};
		$fcache{$name}{channel} = $c;
	}

	return $fcache{$name}{channel};
}

my $app = sub {
	my $env = shift;
	my $req = Plack::Request->new($env);
	my $path = $req->path;
	my $qp = $req->query_parameters;

	$path =~ s|^/||;

	$path = 'index' if !$path;

	if ($path =~ m|/|) {
		my $resp = $req->new_response(400);
		$resp->content_type('text/html');
		$resp->body("<html><h1>400 Bad Request</h1>$path</html>");
		return $resp->finalize;
	} elsif ($path eq 'index') {
		my $resp = $req->new_response(200);
		$resp->content_type('text/html');
		$resp->body(index_doc);
		return $resp->finalize;
	}

	if (! -f "$path.txt") {
		my $resp = $req->new_response(404);
		$resp->content_type('text/html');
		$resp->body("<html><h1>404 Not Found</h1>$path</html>");
		return $resp->finalize;
	}

	my ($rseed, $lines);
	if ($rseed = $qp->{seed}) {
		my $k = "$rseed:$path";

		if ($lines = $pcache->remove($k)) {
			$mcache->set($k => $lines);
		} else {
			$lines = $mcache->get($k)
			|| $mcache->set($k => generate_samples($path, $rseed));
		}

	} else {
		($rseed, $lines) = @{get_channel($path)->get};
		$pcache->set("$rseed:$path" => $lines);
	}

	my $resp = $req->new_response(200);

	if (defined $qp->{plain}) {
		$resp->content_type('text/plain; charset=utf-8');
		$resp->body($lines);
	} else {
		$resp->content_type('text/html; charset=utf-8');
		$resp->body(make_pretty($path, $env->{QUERY_STRING}, $info{$path}{as_list}, $lines, $rseed));
	}

	return $resp->finalize;
};


builder {
	mount '/markov' => builder {
		enable_if { $_[0]->{REMOTE_ADDR} eq '127.0.0.1' } 
			"Plack::Middleware::ReverseProxy";
		$app;
	},
};
