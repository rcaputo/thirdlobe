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
