#!/usr/bin/perl
# $Id$

use warnings;
use strict;

use ThirdLobe::ArcStore;

### Connect to the arc database.

my $kts = ThirdLobe::ArcStore->connect("dbi:Pg:dbname=know", "", "");

### Destroy the database, and rebuild it from scratch.

$kts->rebuild();

### Define some arcs.

my @arcs = (
	[ "is a type of",             "is a type of",   "predicate"         ],
	[ "has the value",            "is a type of",   "predicate"         ],
	[ "is a kind of",             "is a type of",   "predicate"         ],
	[ "Richard Soderberg",        "is a kind of",   "person"            ],
	[ "is a member of",           "is a type of",   "predicate"         ],
	[ "email",                    "is a member of", "Richard Soderberg" ],
	[ "ideas\@crystalflame.net",  "is a type of",   "email"             ],
	[ "name",                     "is a member of", "Richard Soderberg" ],
);

foreach (@arcs) {
	my ($subject, $predicate, $object) = @$_;
	$kts->arc_store($subject, $predicate, $object)
		or die "couldn't store arc ($subject) ($predicate) ($object)";
}

### Define some meta-arcs.

my $email = $kts->arc_fetch("email", "is a member of", "Richard Soderberg");
$kts->arc_store($email, "has the value", "ideas\@crystalflame.net");

my $name = $kts->arc_fetch("name", "is a member of", "Richard Soderberg");
$kts->arc_store($name, "has the value", "Richard Soderberg");

### Start a little shell to investigate what's done.

use Term::ReadLine;
my $term = Term::ReadLine->new("ThirdLobe Shell");
my $prompt = "go: ";

while (defined(my $input = $term->readline($prompt))) {
	print "\n";

	# fetch node
	if ($input =~ /^node\s+(\S.*?)\s*$/) {
		my $anchor = $kts->anchor_fetch($1);
		if ($anchor) {
			print "\tanchor ", $anchor->seq(), " = ", $kts->arc_text($anchor), "\n";
		}
		else {
			print "\tno such node.\n";
		}
		next;
	}

	# fetch relation
	if ($input =~ /^arc\s+\(([^\)]*)\)\s*\(([^\)]*)\)\s*\(([^\)]*)\)/) {
		my ($sub, $prd, $obj) = ($1, $2, $3);
		my @arcs = $kts->arc_fetch($sub, $prd, $obj);

		if (@arcs) {
			foreach my $arc (@arcs) {
				print(
					"\tarc ", $arc->seq(),
					" = (", $arc->sub_seq(),
					",", $arc->prd_seq(),
					",", $arc->obj_seq(),
					") = ", $kts->arc_text($arc), "\n"
				);
			}
		}
		else {
			print "\tno arcs match.\n";
		}
		next;
	}

	if ($input =~ /^\s*(\?|help)\s*$/i) {
		print(
			"\tnode <text> - fetches the anchor for a piece of text\n",
			"\t\tnode email\n",
			"\tarc (<text>) (<text>) (<text>) - search for and define arcs\n",
			"\t<text>s are optional.\n",
			"\t\tarc (has the value) (is a type of) (predicate)\n",
			"\t\tarc () (is a type of) (predicate)\n",
			"\t\tarc () () ()\n",
			"\t^C or Ctrl+C to quit.\n",
		);
		next;
	}

	print "\t? or help for help.\n";
}
continue {
	$term->addhistory($input);
}

while (1){
	print "go> ";
	my $input
}

exit 0;
