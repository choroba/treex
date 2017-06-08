package Treex::Block::Write::SynNN;

use Moose;
use Treex::Core::Common;
use List::MoreUtils "uniq";
extends 'Treex::Block::Write::BaseTextWriter';

has what => ( is => 'rw', isa => 'Str', default => 'sent' );

sub process_atree {
    my ( $self, $aroot ) = @_;

    if ($self->what =~ /^tdInfo|parent|rel$/) {
        # tree-based
        my @result = ();
        # DFS right-to-left traversal
        my @nodes = reverse $aroot->get_children({ordered => 1});
        while (@nodes) {
            my $node = shift @nodes;
            if ($self->what eq 'tdInfo') {
                my @info = ();
                push @info, ($node->ord - 1);
                push @info, ($node->parent->ord - 1);
                push @info, $node->afun;
                push @result, (join '$', @info);
            } else {
                # parent-child type info
                unless ($node->is_leaf) {
                    my @line = $node->get_children({ordered => 1});
                    unshift @line, $node;
                    if ($self->what eq 'parent') {
                        @line = map { $_->ord - 1 } @line;
                    } elsif ($self->what eq 'rel') {
                        @line = map { $_->afun } @line;
                    } else {
                        log_fatal "Unknown value of what: " . $self->what;
                    }
                    push @result, (join ' ', @line);
                }
            }
            unshift @nodes, (reverse $node->get_children({ordered => 1}));
        }
        print { $self->_file_handle } join "\n", @result;
        print { $self->_file_handle } "\n\n";
    } else {
        # token-based
        my @result = ();
        # linear traversal
        foreach my $node ($aroot->get_descendants({ordered => 1})) {
            if ($self->what eq 'sent') {
                push @result, $node->form;
            } elsif ($self->what eq 'pos') {
                push @result, $node->tag;
            } elsif ($self->what eq 'leaves') {
                if ($node->is_leaf) {
                    # TODO the ordering used is weird, maybe should be
                    # reversed DFS order or something like that
                    push @result, ($node->ord - 1);
                }
            } elsif ($self->what eq 'cue') {
                # TODO output based on Write::Negations
                push @result, '0';
            } elsif ($self->what eq 'scope') {
                # TODO output based on Write::Negations
                push @result, '0';
            } else {
                log_fatal "Unknown value of what: " . $self->what;
            }
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
