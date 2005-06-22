# $Id$

=head1 NAME

ThirdLobe::Database - encapsulates ThirdLobe's low-level database operations

=head1 SYNOPSIS

No synopsis yet.

=head1 DESCRIPTION

ThirdLobe::Database abstracts the low-level database operations used
by ThirdLobe::ArcStore.  This class is the reference implementation.
It may eventually move into ThirdLobe::Database::Postgres since it's
based heavily on that database engine.

=cut

package ThirdLobe::Database;

use warnings;
use strict;

use DBI;
use ThirdLobe::Node;
use ThirdLobe::Arc;
use Carp qw(croak);

use constant DBH => 0;

=head1 NODE METHODS

=head2 node_add ANCHOR, TEXT

Adds a node record to the database, associating an ANCHOR arc with
some TEXT.  Returns a ThirdLobe::Node object on success.

TODO - Currently does not have a failure mode.

	my $node_object = $db->node_add($arc_object, "some text");

=cut

sub node_add {
	my ($self, $arc, $text) = @_;
	my $dbh = $self->[DBH];

	# Hash the node's text for its key.
	my $key = $self->_node_hash($text);

	# Insert the node.
	my $sth = $dbh->prepare_cached(
		"INSERT INTO node (arc_seq, val_key, val_text) VALUES (?, ?, ?)"
	);
	$sth->execute($arc->seq(), $key, $text) or die $sth->errstr();
	$sth->finish();

	# Fetch the node back out, with a sequence number and all.
	return $self->node_from_text($text);
}

=head2 _node_hash TEXT

Accepts the TEXT for a node, and returns a version of it that's hashed
for fuzzy retrieval.

The current return value is TEXT that is folded to lowercase, and
whitespace normalized.  More complex algorithms may emerge as usage
dictates.

	my $key = $db->_node_hash("some text");

B<Changing the algorithm will invalidate all your nodes.  Don't do
this lightly.>

=cut

sub _node_hash {
	my ($self, $text) = @_;

	# Simple hashing.  We can do better later.
	my $key = lc($text);
	$key =~ s/\s+/ /g;
	$key =~ s/^\s+//;
	$key =~ s/\s+$//;

	return $key;
}

=head2 node_from_text TEXT

Look up a node record in the database for a given piece of TEXT.
Returns a ThirdLobe::Node object representing the TEXT, or undef on
failure.

	my $node_object = $db->node_from_text("some text");

=cut

sub node_from_text {
	my ($self, $text) = @_;
	my $dbh = $self->[DBH];

	# Hash the node's text for its key.
	my $key = $self->_node_hash($text);

	my $sth = $dbh->prepare_cached("SELECT * FROM node WHERE val_key = ?");
	$sth->execute($key);

	my $row = $sth->fetchrow_hashref();
	$sth->finish();

	return unless $row;
	return ThirdLobe::Node->new($row);
}

=head2 node_from_seq NODE_SEQ

Every node object has a unique, sequential ID assigned to it on
creation.  This is the node table's primary key.

node_from_seq() fetches a node record by this ID and returns a
ThirdLobe::Node object representing it.  Returns undef on failure.

	my $node_object = $db->node_from_seq(42);

=cut

sub node_from_seq {
	my ($self, $node_seq) = @_;
	my $dbh = $self->[DBH];

	my $sth = $dbh->prepare_cached("SELECT * FROM node WHERE seq = ?");
	$sth->execute($node_seq);

	my $row = $sth->fetchrow_hashref();
	$sth->finish();

	return unless $row;
	return ThirdLobe::Node->new($row);
}

=head2 node_from_anchor ANCHOR

Retrieves the node record associated with an anchor arc, and returns a
ThirdLobe::Node representing the record.  Returns undef if there's no
node for the anchor.

	my $node_object = $db->node_from_anchor($arc_object);

=cut

sub node_from_anchor {
	my ($self, $anchor) = @_;
	my $dbh = $self->[DBH];

	my $sth = $dbh->prepare_cached("SELECT * FROM node WHERE arc_seq = ?");
	$sth->execute($anchor->seq());

	my $row = $sth->fetchrow_hashref();
	$sth->finish();

	return unless $row;
	return ThirdLobe::Node->new($row);
}

=head1 ARC METHODS

=head2 build_arc_query SUBJECT_ARC, PREDICATE_ARC, OBJECT_ARC

Builds the SQL WHERE clause and corresponding list of values for
fetching arcs that match up to three arc objects.  Undefined arc
objects act as wildcards.

	my ($where, @values) = $db->build_arc_query(
		$subject_arc, $predicate_arc, $object_arc
	);

=cut

sub build_arc_query {
	my ($self, $sub_anchor, $prd_anchor, $obj_anchor) = @_;

	my (@wheres, @values);
	if (defined $sub_anchor) {
		push @wheres, "sub_seq = ?";
		push @values, $sub_anchor->seq();
	}

	if (defined $prd_anchor) {
		push @wheres, "prd_seq = ?";
		push @values, $prd_anchor->seq();
	}

	if (defined $obj_anchor) {
		push @wheres, "obj_seq = ?";
		push @values, $obj_anchor->seq();
	}

	my $where_clause;
	if (@wheres) {
		$where_clause = " WHERE " . join(" AND ", @wheres);
	}
	else {
		$where_clause = "";
	}

	return $where_clause, @values;
}

=head2 arc_add SUBJECT_ARC, PREDICATE_ARC, OBJECT_ARC

Add an arc that associates three other arcs.  Returns a new
ThirdLobe::Arc object, or undef on failure.

	my $arc = $db->arc_add($subject_arc, $predicate_arc, $object_arc);

=cut

sub arc_add {
	my ($self, $sub_arc, $prd_arc, $obj_arc) = @_;
	my $dbh = $self->[DBH];

	# Insert the arc.
	my $sth = $dbh->prepare_cached(
		"INSERT INTO arc (sub_seq, prd_seq, obj_seq) VALUES (?, ?, ?)"
	);
	$sth->execute($sub_arc->seq(), $prd_arc->seq(), $obj_arc->seq())
		or die $sth->errstr();
	$sth->finish();

	# Fetch the arc back out, with sequence number and all.
	return $self->arc_from_arcs($sub_arc, $prd_arc, $obj_arc);
}

=head2 arc_from_arcs SUBJECT_ARC, PREDICATE_ARC, OBJECT_ARC

Fetch zero or more arcs that match a given SUBJECT_ARC, PREDICATE_ARC,
and OBJECT_ARC.  The three arcs are usually but not always anchors.
Undefined parameters are treated as wildcards.

	my $new_arc = $db->arc_from_arcs(
		$subject_arc, $predicate_arc, $object_arc
	);

=cut

sub arc_from_arcs {
	my ($self, $sub_arc, $prd_arc, $obj_arc) = @_;
	my $dbh = $self->[DBH];

	my ($where_clause, @values) = $self->build_arc_query(
		$sub_arc, $prd_arc, $obj_arc
	);

	my $sth = $dbh->prepare_cached("SELECT * FROM arc" . $where_clause);
	$sth->execute(@values);

	my (%memo, @arcs);
	while (my $row = $sth->fetchrow_hashref()) {

		# The (0,0,0,0) arc doesn't officially exist.
		next unless $row->{seq};

		push @arcs, ThirdLobe::Arc->new($row);
	}
	$sth->finish();

	return @arcs;
}

=head2 arc_count SUBJECT_ARC, PREDICATE_ARC, OBJECT_ARC

Counts the number of arcs that match up to three other arcs.
Undefined parameters are treated as wildcards.  Returns the number of
arcs that were found.

	my $number_found = $db->arc_count(
		$subject_arc, $predicate_arc, $object_arc
	);

=cut

sub arc_count {
	my ($self, $sub_arc, $prd_arc, $obj_arc) = @_;
	my $dbh = $self->[DBH];

	my ($where_clause, @values) = $self->build_arc_query(
		$sub_arc, $prd_arc, $obj_arc
	);

	my $sth = $dbh->prepare_cached(
		"SELECT count(seq) FROM arc" .  $where_clause
	);
	$sth->execute(@values);

	my @row = $sth->fetchrow_array();
	$sth->finish();

	return unless @row;
	return $row[0];
}

=head2 anchor_add

Create a new anchor arc record, and return a ThirdLobe::Arc object to
represent it.

	my $arc_object = $db->anchor_add();

=cut

sub anchor_add {
	my $self = shift;
	my $dbh = $self->[DBH];

	# Insert the arc.
	my $sth = $dbh->prepare_cached(
		"INSERT INTO arc (sub_seq, prd_seq, obj_seq) VALUES (0, 0, 0)"
	);
	$sth->execute() or die $sth->errstr();
	$sth->finish();

	# Return an arc representing it.
	return ThirdLobe::Arc->new(
		{
			db      => $self,
			seq     => $dbh->last_insert_id(undef, undef, "arc", undef),
			sub_seq => 0,
			prd_seq => 0,
			obj_seq => 0,
		}
	);
}

=head2 arc_from_seq ARC_SEQ

Every arc has a unique sequential ID assigned to it.  These IDs are
used as the arc table's primary key.

arc_from_seq() returns a ThirdLobe::Arc object representing the arc
record with a given ARC_SEQ.

	my $arc_object = $db->arc_from_seq(42);

=cut

sub arc_from_seq {
	my ($self, $seq) = @_;
	my $dbh = $self->[DBH];

	my $sth = $dbh->prepare_cached("SELECT * FROM arc WHERE seq = ?");
	$sth->execute($seq);

	# TODO - Error checking.  Return undef on failure.

	my $row = $sth->fetchrow_hashref();
	my $arc = ThirdLobe::Arc->new($row);

	$sth->finish();
	return $arc;
}

=head1 WHOLE DATABASE METHODS

=head2 rebuild

Destroy any data you have, and rebuild the tables and indices the
library will need to actually function.  Must be called after the
database is connected.

	$db->rebuild(); # [SFX: TOILET FLUSHING]

=cut

sub rebuild {
	my $self = shift;
	my $dbh = $self->[DBH];

	warn(
		"++ You may see NOTICEs about implicit triggers being dropped added.\n",
		"++ They appear to be normal.  Please inform us if they can be avoided.\n",
	);

	# Nodes.
	$dbh->do("DROP TABLE node CASCADE");
	$dbh->do("DROP SEQUENCE node_seq_seq");
	$dbh->do("CREATE SEQUENCE node_seq_seq");
	$dbh->do(
		<<'    END'
			CREATE TABLE node (
				seq       INTEGER DEFAULT nextval('node_seq_seq') NOT NULL,
				arc_seq   INTEGER           NOT NULL,
				val_key   CHARACTER VARYING NOT NULL,
				val_text  CHARACTER VARYING NOT NULL
			)
		END
	);
	$dbh->do("CREATE UNIQUE INDEX node_seq ON node USING BTREE (seq)");
	$dbh->do("CREATE INDEX node_arc ON node USING BTREE (arc_seq)");
	$dbh->do("CREATE UNIQUE INDEX node_val_key ON node USING BTREE (val_key)");

	# Arcs.
	$dbh->do("DROP TABLE arc CASCADE");
	$dbh->do("DROP SEQUENCE arc_seq_seq");
	$dbh->do("CREATE SEQUENCE arc_seq_seq");
	$dbh->do(
		<<'    END'
			CREATE TABLE arc (
				seq INTEGER DEFAULT nextval('arc_seq_seq') NOT NULL,
				sub_seq INTEGER NOT NULL,
				prd_seq INTEGER NOT NULL,
				obj_seq INTEGER NOT NULL
			)
		END
	);
	$dbh->do("CREATE UNIQUE INDEX arc_seq ON arc USING BTREE (seq)");
	$dbh->do("CREATE INDEX arc_sub_seq ON arc USING BTREE (sub_seq)");
	$dbh->do("CREATE INDEX arc_prd_seq ON arc USING BTREE (prd_seq)");
	$dbh->do("CREATE INDEX arc_obj_seq ON arc USING BTREE (obj_seq)");

	# Referential integrity.
	$dbh->do(
		"ALTER TABLE node " .
		"ADD CONSTRAINT node_arc " .
		"FOREIGN KEY (arc_seq) " .
		"REFERENCES arc(seq) " .
		"MATCH FULL"
	);

	$dbh->do(
		"ALTER TABLE arc " .
		"ADD CONSTRAINT arc_sub " .
		"FOREIGN KEY (sub_seq) " .
		"REFERENCES arc(seq) " .
		"MATCH FULL"
	);
	$dbh->do(
		"ALTER TABLE arc " .
		"ADD CONSTRAINT arc_prd " .
		"FOREIGN KEY (prd_seq) " .
		"REFERENCES arc(seq) " .
		"MATCH FULL"
	);
	$dbh->do(
		"ALTER TABLE arc " .
		"ADD CONSTRAINT arc_obj " .
		"FOREIGN KEY (obj_seq) " .
		"REFERENCES arc(seq) " .
		"MATCH FULL"
	);

	# For referential integrity to work.
	$dbh->do("INSERT INTO arc VALUES (0, 0, 0, 0)");

	warn "++ End of the NOTICEs.\n";
}

=head2 connect DSN, USERNAME, PASSWORD

Connect to the database, using a DSN, USERNAME, and PASSWORD.
Actually, the parameters to connect() are passed verbatim to
DBI->connect().  Returns a ThirdLobe::Database object that can be used
to interact with the database on a low level.

	my $dbh = ThirdLobe::Database->connect("dbi:pg:dbname=know");

=cut

sub connect {
	my $class = shift;
	my $dbh = DBI->connect(@_);
	die "Could not connect to database: ", $dbh->errstr() if $dbh->err();

	my $self = bless [
		$dbh,  # DBH
	], $class;
}

=head2 DESTROY

The object destructor makes sure that the database is disconnected
from properly.

=cut

sub DESTROY {
	my $self = shift;
	if (defined $self->[DBH]) {
		$self->[DBH]->disconnect();
		$self->[DBH] = undef;
	}
}

=head1 TODO

Many of these methods don't define failure modes if the underlying DBI
calls fail.  They may die outright or return bogus values.  Often the
DBI calls aren't checked for success or failure.

=head1 AUTHORS

ThirdLobe::Database was conceived and written by Rocco Caputo.

Thank you for using it.

=head1 COPYRIGHT

Copyright 2005, Rocco Caputo.

This library is free software; you can use, redistribute it, and/or
modify it under the same terms as Perl itself.

=cut

1;
