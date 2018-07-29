package Treex::Block::INTLIB::Serialize;

## Vincent Kriz, 2014
## Nacte *.treex subor a vypise CSV tabulku podobnu CSTS

use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

has to => (
    is            => 'ro',
    isa           => 'Str',
    default       => '',
    documentation => 'CSV outpout file.',
);

sub process_document {
    my ($self, $document) = @_;
    my $entity_id = 0;

    ## Load XML file
    #my $Document = XML::LibXML->load_xml(location => $filename);

    my %data = ();

    ## Process each sentence
    for my $bundle ($document->get_bundles) {
        for my $zone ($bundle->get_all_zones) {
            for my $tree ($zone->get_all_trees) {
                # Obtain entity tokens
                my @nodes = sort {$a->get_attr('ord') <=> $b->get_attr('ord')} $self->_serialize_sentence($tree);

                foreach my $node (@nodes) {
                    my $text_id = $node->id();
                    $text_id =~ s/^a_tree-(?:cs|en)-(\d+)-.*$/$1/;

                    my $node_id = $node->id();
                    $node_id =~ s/^a_tree-(?:cs|en)-.*-n(\d+)$/$1/;

                    $data{$text_id}{$node_id}{id} = $node->id();
                    $data{$text_id}{$node_id}{ord} = $node->ord();
                    $data{$text_id}{$node_id}{form} = $node->form();
                    $data{$text_id}{$node_id}{lemma} = $node->lemma();
                    $data{$text_id}{$node_id}{parent} = $node->parent()->ord();
                    $data{$text_id}{$node_id}{no_space_after} = $node->no_space_after();
                }
            }
        }
    }

    ## Calculate offsets
    foreach my $text_id (sort keys %data) {
        my $offset = 0;
        foreach my $node_id (sort {$a <=> $b} keys %{$data{$text_id}}) {
            my $form = $data{$text_id}{$node_id}{form};
            $form =~ s/#SPACE#/ /g;

            $data{$text_id}{$node_id}{start} = $offset;
            $data{$text_id}{$node_id}{end} = $offset + length($form);

            $offset += length($form);
            $offset++ if (!$data{$text_id}{$node_id}{no_space_after});
        }
    }

    open(OUTPUT, ">" . $self->to());
    binmode(OUTPUT, ":encoding(utf-8)");
    foreach my $text_id (sort keys %data) {
        foreach my $node_id (sort {$a <=> $b} keys %{$data{$text_id}}) {
            my $form = $data{$text_id}{$node_id}{form};
            $form =~ s/#SPACE#/ /g;

            print OUTPUT join("\t", (
                $data{$text_id}{$node_id}{id},
                $data{$text_id}{$node_id}{ord},
                $form,
                $data{$text_id}{$node_id}{lemma},
                $data{$text_id}{$node_id}{parent},
                $data{$text_id}{$node_id}{start},
                $data{$text_id}{$node_id}{end},
            )) . "\n";
        }
    }
    close(OUTPUT);
}

sub _serialize_sentence {
    my ($self, $node) = @_;
    my @nodes = ();

    push(@nodes, $node) if ($node->get_attr('id') !~ /root/);

    foreach my $child ($node->get_children()) {
        push(@nodes, $self->_serialize_sentence($child));
    }

    return @nodes;
}

1;
