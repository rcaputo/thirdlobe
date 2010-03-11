# $Id$

=head1 NAME

ThirdLobe::Arc - a capsule containing an RDF-like triple

=head1 SYNOPSIS

No synopsis yet.

=head1 DESCRIPTION

ThirdLobe::Arc is a trivial wrapper around a ThirdLobe arc record.

It's not documented.  If you really need to know how it works, ask.
Meanwhile, the source is very short.

=cut

package ThirdLobe::Arc;

use warnings;
use strict;

sub new {
	my ($class, $members) = @_;

	# Copy constructor, since we don't know where the row comes from or
	# whether it will be clobbered.
	my $self = bless { %$members }, $class;
}

sub seq     { return shift()->{seq}     }
sub sub_seq { return shift()->{sub_seq} }
sub prd_seq { return shift()->{prd_seq} }
sub obj_seq { return shift()->{obj_seq} }

sub sub_arc {
	my $self = shift;
	return $self->{sub_arc} if defined $self->{sub_arc};
	return $self->{sub_arc} = $self->{db}->arc_from_seq($self->sub_seq());
}

sub prd_arc {
	my $self = shift;
	return $self->{prd_arc} if defined $self->{prd_arc};
	return $self->{prd_arc} = $self->{db}->arc_from_seq($self->prd_seq());
}

sub obj_arc {
	my $self = shift;
	return $self->{obj_arc} if defined $self->{obj_arc};
	return $self->{obj_arc} = $self->{db}->arc_from_seq($self->obj_seq());
}

sub sub_node {
	my $self = shift;
	return $self->{sub_node} if defined $self->{sub_node};
	return $self->{sub_node} = $self->{db}->node_from_anchor( $self->sub_arc() );
}

sub prd_node {
	my $self = shift;
	return $self->{prd_node} if defined $self->{prd_node};
	return $self->{prd_node} = $self->{db}->node_from_anchor( $self->prd_arc() );
}

sub obj_node {
	my $self = shift;
	return $self->{obj_node} if defined $self->{obj_node};
	return $self->{obj_node} = $self->{db}->node_from_anchor( $self->obj_arc() );
}

sub subject {
	my $self = shift;
	return $self->{sub_text} if defined $self->{sub_text};

	my $sub_node = $self->sub_node();
	return $self->{sub_text} = $sub_node->val() if defined $sub_node;
	return $self->{sub_text} = $self->{sub_arc};
}

sub predicate {
	my $self = shift;
	return $self->{prd_text} if defined $self->{prd_text};

	my $prd_node = $self->prd_node();
	return $self->{prd_text} = $prd_node->val() if defined $prd_node;
	return $self->{prd_text} = $self->{prd_arc};
}

sub object {
	my $self = shift;
	return $self->{obj_text} if defined $self->{obj_text};

	my $obj_node = $self->obj_node();
	return $self->{obj_text} = $obj_node->val() if defined $obj_node;
	return $self->{obj_text} = $self->{obj_arc};
}

=head1 BUGS

ThirdLobe::Arc objects are independent of each other, even if two or
more represent the same record.  This isn't an issue at the moment,
but it may become one at a point in the future when arcs may be
deleted.  A flyweight pattern may be better then.

=head1 AUTHORS

ThirdLobe::Arc was conceived and written by Rocco Caputo.

Thank you for using it.

=head1 COPYRIGHT

Copyright 2005, Rocco Caputo.

This library is free software; you can use, redistribute it, and/or
modify it under the same terms as Perl itself.

=cut

1;
