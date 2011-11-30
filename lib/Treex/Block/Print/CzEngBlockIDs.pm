package Treex::Block::Print::CzEngBlockIDs;
use Moose;
use Treex::Core::Common;
use Treex::Tool::Coreference::ValueTransformer;

extends 'Treex::Core::Block';

sub process_document {

    my ( $self, $document ) = @_;

    print $document->full_filename;

    my @outids = ();
    foreach my $bundle ( $document->get_bundles() ) {
        if ($bundle->wild->{"segm_break"} && 0 < scalar @outids) {
            print "\t";
            print join(" ", @outids);
            @outids = ();
        }
        push @outids, $bundle->id;
    }
    print "\n";
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME 

Treex::Block::Print::CzEngBlockIDs

=head1 DESCRIPTION

Prints for each document one line with document ID and then a sequence of
tab-delimited blocks -- segment IDs that belong together.

=head1 AUTHORS

Ondřej Bojar <bojar@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2011 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
