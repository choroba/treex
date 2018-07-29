package Treex::Block::INTLIB::Retokenize;

## Vincent Kriz, 2014
## Retokenizuje reference na pravni dokumnety.

use Moose;
use Treex::Core::Common;
extends 'Treex::Core::Block';

sub process_document {
    my ($self, $document) = @_;
    my $sentence_id = 0;

    for my $b ($document->get_bundles) {
        for my $z ($b->get_all_zones) {
            for my $t ($z->get_all_trees) {
                print STDERR "\n\n[SENT] ================================\n\n";
                while (42) {
                    my $zmena = 0;
                    my @nodes = $self->_serialize_sentence($t);
                    for (my $i = 0; $i < scalar(@nodes); $i++) {
                        #print STDERR "[DEBUG] \$nodes[$i]->get_attr('form') = " . $nodes[$i]->get_attr('form') . "\n";
                        #print STDERR "[DEBUG] \$nodes[$i + 1]->get_attr('form') = " . $nodes[$i + 1]->get_attr('form') . "\n";
                        #print STDERR "\n";

                        # PISMENO + )
                        if ($i < scalar(@nodes) - 1 and
                            $nodes[$i]->get_attr('form') =~ /^[a-z]$/ and
                            $nodes[$i + 1]->get_attr('form') =~ /^\)$/) {

                            print STDERR "[JOIN] " . $nodes[$i]->get_attr('form') . $nodes[$i + 1]->form() . "\n";
                            $nodes[$i]->set_attr('form', $nodes[$i]->get_attr('form') . $nodes[$i + 1]->form());
                            $nodes[$i]->set_attr('no_space_after', $nodes[$i + 1]->get_attr('no_space_after'));
                            $nodes[$i]->set_attr('joined', 1);

                            $nodes[$i + 1]->remove();
                            delete($nodes[$i + 1]);

                            $zmena = 1;
                            last;
                        }
                        
                        # Sb + .
                        if ($i < scalar(@nodes) - 1 and
                            $nodes[$i]->get_attr('form') =~ /^Sb$/ and
                            $nodes[$i + 1]->get_attr('form') =~ /^\.$/) {

                            print STDERR "[JOIN] " . $nodes[$i]->get_attr('form') . $nodes[$i + 1]->form() . "\n";
                            $nodes[$i]->set_attr('form', $nodes[$i]->get_attr('form') . $nodes[$i + 1]->form());
                            $nodes[$i]->set_attr('no_space_after', $nodes[$i + 1]->get_attr('no_space_after'));
                            $nodes[$i]->set_attr('joined', 1);

                            $nodes[$i + 1]->remove();
                            delete($nodes[$i + 1]);

                            $zmena = 1;
                            last;
                        }

                        # LABEL + . + CISLO / PISMENO / SLASH-CISLO
                        if ($i < scalar(@nodes) - 2 and
                            $nodes[$i]->get_attr('form') =~ /^(č|čl|odst|písm)$/i and
                            $nodes[$i + 1]->get_attr('form') =~ /^\.$/ and
                            $nodes[$i + 2]->get_attr('form') =~ /^(\d+[a-z]?|\d+\/\d+|[a-z]\))$/) {

                            print STDERR "[JOIN] " . $nodes[$i]->get_attr('form') . ".#SPACE#" . $nodes[$i + 2]->form() . "\n";
                            $nodes[$i]->set_attr('form', $nodes[$i]->get_attr('form') . ".#SPACE#" . $nodes[$i + 2]->form());
                            $nodes[$i]->set_attr('no_space_after', $nodes[$i + 2]->get_attr('no_space_after'));
                            $nodes[$i]->set_attr('joined', 1);
    
                            $nodes[$i + 1]->remove();
                            $nodes[$i + 2]->remove();
                            delete($nodes[$i + 1]);
                            delete($nodes[$i + 2]);

                            $zmena = 1;
                            last;
                        }

                        # LABEL + CISLO / PISMENO / SLASH-CISLO
                        if ($i < scalar(@nodes) - 1 and
                            $nodes[$i]->get_attr('form') =~ /^(odstav(ec|ce|ci|cem|ců|cům|cích|cech)|§|písmen(o|a|u|em|ům|ami|y)?|bod(u|em|y|ů|ům|ech|y)?)$/ and
                            $nodes[$i + 1]->get_attr('form') =~ /^(\d+[a-z]?|\d+\/\d+|[a-z]\))$/) {

                            print STDERR "[JOIN] " . $nodes[$i]->get_attr('form') . "#SPACE#" . $nodes[$i + 1]->form() . "\n";
                            $nodes[$i]->set_attr('form', $nodes[$i]->get_attr('form') . "#SPACE#" . $nodes[$i + 1]->form());
                            $nodes[$i]->set_attr('no_space_after', $nodes[$i + 1]->get_attr('no_space_after'));
                            $nodes[$i]->set_attr('joined', 1);

                            $nodes[$i + 1]->remove();
                            delete($nodes[$i + 1]);

                            $zmena = 1;
                            last;
                        }

                        # JOINED + SPOJKA + JOINED / CISLO / PISMENO / SLASH-CISLO
                        if ($i < scalar(@nodes) - 2 and
                            defined($nodes[$i]->get_attr('joined')) and
                            $nodes[$i + 1]->get_attr('form') =~ /^(a|nebo|až|,)$/ and
                            ($nodes[$i + 2]->get_attr('form') =~ /^(\d+[a-z]?|\d+\/\d+|[a-z]\))$/ or
                            defined($nodes[$i + 2]->get_attr('joined')))) {

                            my $new_form = $nodes[$i]->get_attr('form');
                            $new_form .= "#SPACE#" if ($nodes[$i + 1]->get_attr('form') ne ",");
                            $new_form .= $nodes[$i + 1]->get_attr('form');
                            $new_form .= "#SPACE#";
                            $new_form .= $nodes[$i + 2]->get_attr('form');

                            print STDERR "[JOIN] $new_form\n";
                            $nodes[$i]->set_attr('form', $new_form);
                            $nodes[$i]->set_attr('no_space_after', $nodes[$i + 2]->get_attr('no_space_after'));
                            $nodes[$i]->set_attr('joined', 1);

                            $nodes[$i + 1]->remove();
                            $nodes[$i + 2]->remove();
                            delete($nodes[$i + 1]);
                            delete($nodes[$i + 2]);

                            $zmena = 1;
                            last;
                        }

                        # JOINED + JOINED
                        if ($i < scalar(@nodes) - 1 and
                            defined($nodes[$i]->get_attr('joined')) and
                            defined($nodes[$i + 1]->get_attr('joined'))) {

                            my $new_form = $nodes[$i]->get_attr('form');
                            $new_form .= "#SPACE#";
                            $new_form .= $nodes[$i + 1]->get_attr('form');

                            print STDERR "[JOIN] $new_form\n";
                            $nodes[$i]->set_attr('form', $new_form);
                            $nodes[$i]->set_attr('no_space_after', $nodes[$i + 1]->get_attr('no_space_after'));
                            $nodes[$i]->set_attr('joined', 1);

                            $nodes[$i + 1]->remove();
                            delete($nodes[$i + 1]);

                            $zmena = 1;
                            last;
                        }
                    }

                    if (!$zmena) {
                        last;
                    }
                }
            }
        }
    }
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
