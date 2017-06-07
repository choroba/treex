package Treex::Block::Write::SynNN;

use Moose;
use Treex::Core::Common;
use List::MoreUtils "uniq";
extends 'Treex::Block::Write::BaseTextWriter';

has what => ( is => 'rw', isa => 'Str', default => 'sent' );

sub process_atree {
    my ( $self, $aroot ) = @_;

    my @descendants = $aroot->get_descendants({ordered => 1});

    if ($self->what eq 'sent') {
        my @result = ();
        foreach my $node (@descendants) {
            push @result, $node->form;
        }
        print { $self->_file_handle } join ' ', @result;
        print { $self->_file_handle } "\n";
    } elsif ($self->what eq 'pos') {
        my @result = ();
        foreach my $node (@descendants) {
            push @result, $node->tag;
        }
        print { $self->_file_handle } join ' ', @result;
        print { $self->_file_handle } "\n";
    }
    
    return;
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Treex::Block::Write::SynNN

=head1 DESCRIPTION

Writes out data in the format required by SynNN and NegNN tools of Federico Fancellu.

There are 7 files needed, each invocation of this block creates onw of them, according to the value of the C<what> parameter, which must be one of:

=over

=item tdInfo

=item parent

=item rel

=item leaves

=item pos

=item sent

=item cue

=item scope

=back

=head1 AUTHOR

Rudolf Rosa

=head1 COPYRIGHT AND LICENSE

Copyright © 2017 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
