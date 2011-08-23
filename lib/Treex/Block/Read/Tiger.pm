package Treex::Block::Read::Tiger;
use Moose;
use Treex::Core::Common;
extends 'Treex::Block::Read::BaseReader';
use XML::Twig;

has bundles_per_doc => (
    is => 'ro',
    isa => 'Int',
    default => 0,
);

has language => ( isa => 'LangCode', is => 'ro', required => 1 );

has _twig => (isa    => 'XML::Twig',
              is     => 'ro',
              writer => '_set_twig',
             );

sub BUILD {
    my ($self) = @_;
    if ( $self->bundles_per_doc ) {
        $self->set_is_one_doc_per_file(0);
    }
    $self->_set_twig(XML::Twig::->new());
    return;
}


sub next_document {
    my ($self) = @_;
    my $filename = $self->next_filename();
    return if !defined $filename;
    log_info "Loading $filename...";

    my $document = $self->new_document();
    $self->_twig->setTwigRoots(
        { s => sub {
              my ($twig, $sentence) = @_;
              my $bundle = $document->create_bundle;
              my $zone = $bundle->create_zone($self->language, $self->selector);
              my $ptree = $zone->create_ptree;
              my @edges;
              foreach my $nonterminal ($sentence->descendants('nt')) {
                  my $ch = $ptree->create_nonterminal_child();
                  $ch->set_id($nonterminal->{att}{id});
                  $ch->set_phrase($nonterminal->{att}{cat});
                  push @edges, [ $ch, @{ $_->{att} }{qw/idref label/} ]
                      for $nonterminal->children('edge');
              }
              foreach my $terminal ($sentence->descendants('t')) {
                  my $ch = $ptree->create_terminal_child();
                  $ch->set_id($terminal->{att}{id});
                  $ch->set_form($terminal->{att}{word});
                  $ch->set_lemma($terminal->{att}{lemma});
                  $ch->set_tag($terminal->{att}{pos} . $terminal->{att}{morph});
              }
              foreach my $edge (@edges) {
                  my ($parent, $child_id, $label) = @$edge;
                  my ($child) = grep $child_id eq $_->id, $ptree->descendants;
                  $child->set_parent($parent);
                  $child->set_is_head($label);
              }
          }, # sentence handler
        });

    $self->_twig->parsefile($filename);
    $self->_twig->purge;

    return $document;
} # next_document


1;

__END__

=head1 NAME

Treex::Block::Read::Tiger

=head1 DESCRIPTION

Document reader for the XML-based Tiger format used for storing
German TIGER Treebank.

=head1 METHODS

=over

=item next_document

Loads a document.

=back

=head1 PARAMETERS

=over

none

=head1 SEE

L<Treex::Block::Read::BaseReader>

=head1 AUTHOR

Jan Štěpánek

=head1 COPYRIGHT AND LICENSE

Copyright © 2011 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
