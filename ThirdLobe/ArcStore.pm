=head1 NAME

ThirdLobe::ArcStore - a class to represent an RDF-like triples database

=head1 SYNOPSIS

	use ThirdLobe::ArcStore;

	my $as = ThirdLobe::ArcStore->connect(
		"dbi:Pg:dbname=know", "username", "password"
	);

	# Drop everything and rebuild the tables from scratch.  Destructive.
	$as->rebuild();

	# Store an arc's text, creating a ThirdLobe::Arc object or fetching
	# one if the arc already exsts.
	$as->arc_store("subject", "predicate", "object");

	# Fetch an arc (ThirdLobe::Arc object).
	my $arc = $as->arc_fetch("subject", "predicate", "object");

	# Resolve a ThirdLobe::Arc object as text.
	print $as->arc_text($arc), "\n";

=head1 DESCRIPTION

ThirdLobe::ArcStore is an abstraction for the particular kind of
RDF-like triples database needed by the ThirdLobe project.

TODO - Explain the peculiarities.
TODO - Explain the database.

ThirdLobe uses the term "arc" to describe triples.  Arcs in
mathematics are defined by three points.  In ThirdLobe, each point
represents some sort of idea.  Each "arc" record in the database
consists of its own unique ID, and the unique IDs of three other arcs:
the subject, predicate and object that the arc ties together.

"Nodes" in ThirdLobe are the ideas themselves.  They are kept in a
separate table from arcs.  Each node record consists of: its own
unique ID, the unique ID of an anchor that represents it, the text
that describes the idea, and a hashed version of the text for
searching.

ThirdLobe's anchors are arcs with zeroed subjects, predicates, and
objects.  They represent nodes within the arc database.

=cut

package ThirdLobe::ArcStore;

use warnings;
use strict;

use ThirdLobe::Database;
use Scalar::Util qw(blessed);
use Carp qw(croak);

use constant DB => 0;

sub _db { return shift()->[DB] }

=head1 METHODS

=head2 rebuild

Rebuilds the arc database by dropping any existing ThirdLobe tables
and re-creating them from scratch.  B<This will destroy your existing
ThirdLobe data.>

	$as->rebuild();  # Bye bye!

=cut

sub rebuild {
	my $self = shift;
	$self->_db()->rebuild();
}

=head2 connect DSN, USERNAME, PASSWORD

Connect to a ThirdLobe arc database.  It returns a ThirdLobe::ArcStore
object that can be used to store and fetch arcs.  It dies if the
connection can't be made.

	my $arc_store = ThirdLobe::ArcStore->connect(
		"dbi:Pg:dbname=know", "username", "password"
	);

=cut

sub connect {
	my $class = shift;
	my $dbh = ThirdLobe::Database->connect(@_);

	my $self = bless [
		$dbh, # DB
	], $class;
}

=head2 arc_store SUBJECT_TEXT, PREDICATE_TEXT, OBJECT_TEXT

Creates node records for SUBJECT_TEXT, PREDICATE_TEXT, and
OBJECT_TEXT, then creates an arc record to associate them.  Returns a
ThirdLobe::Arc object represeting the stored arc.  Dies on failure.

Pre-existing nodes and arcs are reused if they already exist.

=cut

sub arc_store {
	my ($self, $subject, $predicate, $object) = @_;
	my $db = $self->_db();

	my $sub;
	if (ref($subject)) {
		unless (blessed($subject) and $subject->isa("ThirdLobe::Arc")) {
			croak "arc_store() subject must be text or a ThirdLobe::Arc object";
		}
		$sub = $subject;
	}
	else {
		$sub = $self->anchor_store($subject);
	}

	my $prd;
	if (ref($predicate)) {
		unless (blessed($predicate) and $predicate->isa("ThirdLobe::Arc")) {
			croak "arc_store() predicate must be text or a ThirdLobe::Arc object";
		}
		$prd = $predicate;
	}
	else {
		$prd = $self->anchor_store($predicate);
	}

	my $obj;
	if (ref($object)) {
		unless (blessed($object) and $object->isa("ThirdLobe::Arc")) {
			croak "arc_store() object must be text or a ThirdLobe::Arc object";
		}
		$obj = $object;
	}
	else {
		$obj = $self->anchor_store($object);
	}

	# TODO - Fetch the arc and return it, otherwise add it.

	my @arcs = $db->arc_from_arcs($sub, $prd, $obj);
	unless (@arcs) {
		@arcs = $db->arc_add($sub, $prd, $obj);
	}

	die "@arcs" unless @arcs == 1;

	return $arcs[0];
}

=head2 arc_fetch SUBJECT_TEXT, PREDICATE_TEXT, OBJECT_TEXT

Attempt to fetch one or more arcs from the database, based on the text
of subject, predicate, and object nodes.  It returns all the arcs that
have been found if it's called in list context.  When called in scalar
context, it retuns one of the found arcs at random.

In either case it returns false (undef, empty list) if it fails.  It
can fail if SUBJECT_TEXT, PREDICATE_TEXT, or OBJECT_TEXT doesn't
exist.  It can fail if no arcs are found.

There's no reason to call it in list context if you expect only one
result:

	my $arc = $arc_store->arc_fetch("subject", "predicate", "object");

Any combination of SUBJECT_TEXT, PREDICATE_TEXT, and OBJECT_TEXT may
be undefined.  Undefined parameters act as wildcards, which may lead
to multiple return values.

	my @arcs = $arc_store->arc_fetch("subject", undef, undef);

Every returned arc is represented by a ThirdLobe::Arc object.  Large
return sets may consume a lot of memory.

=cut

sub arc_fetch {
	my ($self, $subject, $predicate, $object, $limit) = @_;

	my $sub;
	if (defined $subject and length $subject) {
		if (ref($subject) eq 'ThirdLobe::Arc') {
			$sub = $subject;
		}
		else {
			$sub = $self->anchor_fetch($subject);
			return unless defined $sub;
		}
	}

	my $prd;
	if (defined $predicate and length $predicate) {
		if (ref($predicate) eq 'ThirdLobe::Arc') {
			$prd = $predicate;
		}
		else {
			$prd = $self->anchor_fetch($predicate);
			return unless defined $prd;
		}
	}

	my $obj;
	if (defined $object and length $object) {
		if (ref($object) eq 'ThirdLobe::Arc') {
			$obj = $object;
		}
		else {
			$obj = $self->anchor_fetch($object);
			return unless defined $obj;
		}
	}

	my @arcs = $self->_db()->arc_from_arcs($sub, $prd, $obj, $limit);

	return unless @arcs;
	return @arcs if wantarray;
	return $arcs[rand @arcs];
}

=head2 anchor_store TEXT

Store some text in the database without an association attached to it.
Return a ThirdLobe::Arc object representing the new anchor, or false
if the anchor TEXT could not be stored.

	my $arc = $arc_store->anchor_store("an idea");

anchor_store() is mostly used internally by ThirdLobe::ArcStore.

=cut

sub anchor_store {
	my ($self, $text) = @_;

	# TODO - Return node if it exists, otherwise add and return.
	my $node = $self->_db()->node_from_text($text);
	return $self->_db()->arc_from_seq($node->arc_seq()) if $node;

	my $anchor = $self->_db()->anchor_add();
	$self->_db()->node_add($anchor, $text);
	return $anchor;
}

=head2 anchor_fetch TEXT

Retrieve an anchor arc by its text.  Returns a ThirdLobe::Arc object
representing the anchor, or false if the text has no anchor.

	my $anchor = $arc_store->anchor_fetch("an idea");

anchor_fetch() is mostly used internally by ThirdLobe::ArcStore.

=cut

sub anchor_fetch {
	my ($self, $text) = @_;

	my $node = $self->_db()->node_from_text($text);
	return unless $node;

	return $self->_db()->arc_from_seq($node->arc_seq());
}

=head2 arc_text ARC

Resolve a ThirdLobe::Arc object into the human-readable text that it
describes.  Returns some text on success, or undef on failure.

	my $text = $arc_store->arc_text($arc_object);
	print "$text\n";

arc_text() is the entry point into a recursive walk down the arc
network that begins with a given ARC.  The resulting text may not be
very human readable, but it should be fairly unambiguous when read
closely.

A better output format would certainly be nice.  Send your suggestions
if you'd like them considered.

=cut

sub arc_text {
	my ($self, $arc) = @_;
	return $self->_arc_text_recursive({ }, $arc);
}

### Here's the recursive part.

sub _arc_text_recursive {
	my ($self, $arc_cache, $arc) = @_;

	# If this arc's subject sequence number is 0, then it's a node.
	# Technically I should check the predicate and object sequence
	# numbers, but they should be all or none zero.

	my $sub_seq = $arc->sub_seq();
	my $arc_seq = $arc->seq();
	unless ($sub_seq) {
		unless (exists $arc_cache->{$arc_seq}) {
			my $node = $self->_db()->node_from_anchor($arc);
			$arc_cache->{$arc_seq} = $node->val();
		}
		return $arc_cache->{$arc_seq};
	}

	# Otherwise we'll have to recursively fetch the subject, predicate,
	# and object texts.

	unless (exists $arc_cache->{$sub_seq}) {
		my $sub_arc = $self->_db()->arc_from_seq($sub_seq);
		$arc_cache->{$sub_seq} = $self->_arc_text_recursive($arc_cache, $sub_arc);
	}
	my $sub_text = $arc_cache->{$sub_seq};

	my $prd_seq = $arc->prd_seq();
	unless (exists $arc_cache->{$prd_seq}) {
		my $prd_arc = $self->_db()->arc_from_seq($prd_seq);
		$arc_cache->{$prd_seq} = $self->_arc_text_recursive($arc_cache, $prd_arc);
	}
	my $prd_text = $arc_cache->{$prd_seq};

	my $obj_seq = $arc->obj_seq();
	unless (exists $arc_cache->{$obj_seq}) {
		my $obj_arc = $self->_db()->arc_from_seq($obj_seq);
		$arc_cache->{$obj_seq} = $self->_arc_text_recursive($arc_cache, $obj_arc);
	}
	my $obj_text = $arc_cache->{$obj_seq};

	return "($sub_text) ($prd_text) ($obj_text)";
}

######## These are unused.

### Fetch a ThirdLobe::Node by the text stored within it.
### Do we need this?

#sub node_fetch {
#	my ($self, $text) = @_;
#  return $self->_db()->node_from_text($text);
#}

### Store a node by its text.  Also creates an anchor.  Because we're
### storing a NODE, we return a ThirdLobe::Node.  Do we even need
### this?

#sub node_store {
#	my ($self, $text) = @_;
#
#  my $node = $self->_db()->node_from_text($text);
#	return $node if defined $node;
#
#	my $anchor = $self->_db()->anchor_add();
#	return $self->_db()->node_add($anchor, $text);
#}

=head1 AUTHORS

ThirdLobe::ArcStore was conceived and written by Rocco Caputo.

Thank you for using it.

=head1 COPYRIGHT

Copyright 2005-2010, Rocco Caputo.

This library is free software; you can use, redistribute it, and/or
modify it under the same terms as Perl itself.

=cut

1;
