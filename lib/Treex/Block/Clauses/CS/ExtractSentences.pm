package Treex::Block::Clauses::CS::ExtractSentences;

use Moose;
use Treex::Core::Common;
use Treex::Core::Config;
use Treex::Tool::Transliteration::DowngradeUTF8forISO2;

use Treex::Block::Clauses::CS::Parse;

extends 'Treex::Core::Block';

has 'lemmas' => (
    is       => 'ro',
    isa      => 'Int',
    default  => 0
);

has 'cgs' => (
    is       => 'ro',
    isa      => 'Str',
    default  => ''
);

sub encode_special_forms {
    my ($self, $input_form) = @_;

    if ($input_form eq '|') {
        return '&verbar;'
    }

    if ($input_form eq '%') {
        return '&percnt;'
    }

    if ($input_form eq '*') {
        return '&ast;'
    }

    if ($input_form eq '&') {
        return '&amp;'
    }

    if ($input_form eq '_') {
        return '&lowbar;'
    }

    if ($input_form eq '>') {
        return '&gt;'
    }

    if ($input_form eq '<') {
        return '&lt;'
    }



    return $input_form;
}

sub process_atree {
    my ($self, $a_root) = @_;

    # Obtain the sentence clause structure (SCS).
    my $cg = Treex::Block::Clauses::CS::Parse::get_clause_chart(undef, $a_root);
    my $sstructure = Treex::Block::Clauses::CS::Parse::init_clause_structure(undef, $a_root);

    if ($self->cgs ne '') {
        my @allowed_cgs = split(/,/, $self->cgs);
        log_info("Allowed CGs: @allowed_cgs");
        if (scalar(grep(/^$cg$/, @allowed_cgs)) == 0) {
            log_info("Skipping disabled Clause Chart $cg");
            return;
        }
    }

    # Filter out nodes to be used.
    my @nodes = $a_root->get_descendants({ordered => 1});

    # Extract data.
    my (@forms, @tags, @afuns, @parents) = ((), (), (), ());
    foreach my $node (@nodes) {
        # Forms or lemmas.
        if ($self->lemmas == 0) {
            push(@forms, $self->encode_special_forms($node->form));
        }
        else {
            push(@forms, $self->encode_special_forms($node->lemma));
        }

        # Parents.
        push(@parents, $node->parent->ord);

        # Afuns.
        my $afun = $node->afun;
        if ($node->is_member()) {
            my $founded_head = 0;
            my $parent = $node->parent;
            while ($parent->parent) {
                if ($parent->afun eq 'Coord') {
                    $afun .= '_Co';
                    $founded_head = 1;
                    last;
                }

                if ($parent->afun eq 'Apos') {
                    $afun .= '_Ap';
                    $founded_head = 1;
                    last;
                }

                $parent = $parent->parent;
            }

            if (!$founded_head) {
                log_fatal('Unknown afun modification -> ' . $node->id);
            }
        }
        if ($node->get_attr('is_parenthesis_root')) {
            $afun .= '_Pa';
        }
        push(@afuns, $afun);

        # Tags
        my @p = split(//, $node->tag);
        push(@tags, ($p[4] eq '-') ? ($p[0] . $p[1]) : ($p[0] . $p[4]));
    }

    # print "\n";
    # print $a_root->id;
    # print "\n";
    print Treex::Tool::Transliteration::DowngradeUTF8forISO2::downgrade_utf8_for_iso2(join("\t", @forms)) . "\n";
    print Treex::Tool::Transliteration::DowngradeUTF8forISO2::downgrade_utf8_for_iso2(join("\t", @tags)) . "\n";
    print Treex::Tool::Transliteration::DowngradeUTF8forISO2::downgrade_utf8_for_iso2(join("\t", @afuns)) . "\n";
    print Treex::Tool::Transliteration::DowngradeUTF8forISO2::downgrade_utf8_for_iso2(join("\t", @parents)) . "\n";
    print "\n";

    # Consider each 0-clause as individual sentence and print it in MCD format to the STDOUT.
    # foreach my $block (@$sstructure) {
    #     my @nodes = @{$block->{nodes}};

    #     # Extract only 0-clauses.
    #     if ($block->{type} ne 'clause' or $block->{deep} != 0) {
    #         next;
    #     }

    #     # Obtain the mapping between the ords from the whole, global tree
    #     # and the local, clause tree.
    #     my %g2l = ();
    #     for (my $i = 0; $i < @nodes; $i++) {
    #         my $node = $nodes[$i];
    #         $g2l{$node->ord} = $i + 1;
    #     }

    #     # Extract data.
    #     my (@forms, @tags, @afuns, @parents) = ((), (), (), ());
    #     foreach my $node (@{$block->{nodes}}) {
    #         push(@forms, $node->form);
    #         push(@afuns, $node->afun);

    #         my $parent = $node->parent->ord;
    #         push(@parents, defined($g2l{$parent}) ? $g2l{$parent} : 0);

    #         my @p = split(//, $node->tag);
    #         push(@tags, ($p[4] eq '-') ? ($p[0] . $p[1]) : ($p[0] . $p[4]));
    #     }

    #     # print join("\t", @forms) . "\n";
    #     # print join("\t", @tags) . "\n";
    #     # print join("\t", @afuns) . "\n";
    #     # print join("\t", @parents) . "\n\n";

    #     print Treex::Tool::Transliteration::DowngradeUTF8forISO2::downgrade_utf8_for_iso2(join("\t", @forms)) . "\n";
    #     print Treex::Tool::Transliteration::DowngradeUTF8forISO2::downgrade_utf8_for_iso2(join("\t", @tags)) . "\n";
    #     print Treex::Tool::Transliteration::DowngradeUTF8forISO2::downgrade_utf8_for_iso2(join("\t", @afuns)) . "\n";
    #     print Treex::Tool::Transliteration::DowngradeUTF8forISO2::downgrade_utf8_for_iso2(join("\t", @parents)) . "\n";
    #     print "\n";
    # }
}

1;

__END__

=over

=item Treex::Block::Clauses::CS::Extract0

This block extract 0-clauses in the MCD format suitable for traing of the 
McDonald's MST parser adapted by Zdenek Zabokrtsky and Vaclav Novak.

=back

=cut

=head1 COPYRIGHT AND LICENSE

Copyright © 2017 by Vincent Kriz <kriz@ufal.mff.cuni.cz>

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
