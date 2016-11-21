package Treex::Block::Clauses::CS::Eval0B1;

use Moose;
use Treex::Core::Common;
use Treex::Block::Clauses::CS::Parse;

extends 'Treex::Core::Block';

has 'clause_chart_threshold' => (
    is       => 'ro',
    isa      => 'Num',
    default  => 0
);

sub process_bundle {
    my ($self, $bundle) = @_;

    # Gold-standard.
    my $ref_zone = $bundle->get_zone($self->language, $self->selector);
    my @ref_parents = map { $_->get_parent->ord } $ref_zone->get_atree->get_descendants({ordered => 1});
    my $ref_label = $ref_zone->get_label;

    # Clause chart
    my $clause_chart = Treex::Block::Clauses::CS::Parse::get_clause_chart(undef, $ref_zone->get_atree);
    if ($clause_chart ne '0B1') {
        return;
    }

    # Extract lexicalized boundary.
    my $clause_structure = Treex::Block::Clauses::CS::Parse::init_clause_structure(undef, $ref_zone->get_atree);
    my $lexicalized_boundary = '';
    foreach my $block (@$clause_structure) {
        if ($block->{type} eq 'boundary') {
            $lexicalized_boundary = join('_', map {$_->lemma} @{$block->{nodes}});
            last;
        }
    }

    # Zoned to be evaluated and reported.
    my @compared_zones = grep { $_ ne $ref_zone && $_->language eq $self->language } $bundle->get_all_zones();
    $self->{compared_zones} = \@compared_zones;

    foreach my $compared_zone (@compared_zones) {
        my $label = $compared_zone->get_label;
        my @parents = map { $_->get_parent->ord } $compared_zone->get_atree->get_descendants({ordered => 1});

        if (@parents != @ref_parents) {
            log_fatal("There must be the same number of nodes in compared trees");
        }

        foreach my $i (0 .. $#parents) {
            my $eqp = $parents[$i] == $ref_parents[$i];

            $self->{stats}{total}{$label}{correct}++ if($eqp);
            $self->{stats}{$lexicalized_boundary}{$label}{correct}++ if($eqp);
        }

        $self->{stats}{total}{$label}{total} += @parents;
        $self->{stats}{$lexicalized_boundary}{$label}{total} += @parents;
    }

    $self->{n_sentences}{total}++;
    $self->{n_sentences}{$lexicalized_boundary}++;

    $self->{n_nodes}{total} += @ref_parents;
    $self->{n_nodes}{$lexicalized_boundary} += @ref_parents;

    return;
}

sub print_stats {
    my ($self) = @_;

    print "\n";
    print "**********\n";
    print "EVALUATION\n";
    print "**********\n";
    print "\n";

    # List of zone labels.
    my @compared_zones_labels = map { $_->get_label } @{$self->{compared_zones}};

    # Border.
    my $border = sprintf("%10s-+-%10s-+-%10s-+-%10s-+-%s\n", "----------", "----------", "----------", "----------", join("", map { sprintf("%11s-+-", "-----------") } @compared_zones_labels));

    # Header.
    printf("%10s | %10s | %10s | %10s | %s\n", "subset", "#sents", "#nodes", "weight", join("", map { sprintf("%11s | ", $_) } @compared_zones_labels));
    print $border;

    # Subset below threshold.
    $self->{n_sentences}{other} = 0;
    $self->{n_nodes}{other} = 0;
    foreach my $compared_zone_label (@compared_zones_labels) {
        $self->{stats}{other}{$compared_zone_label}{correct} = 0;
        $self->{stats}{other}{$compared_zone_label}{total} = 0;
    }

    # UAS for different subsets.
    foreach my $subset (reverse sort { $self->{n_nodes}{$a} <=> $self->{n_nodes}{$b} } keys %{$self->{stats}}) {
        my $weight = $self->{n_nodes}{$subset} / $self->{n_nodes}{total};

        # Clause chart agregation.
        if ($weight < $self->clause_chart_threshold) {
            $self->{n_sentences}{other} += $self->{n_sentences}{$subset};
            $self->{n_nodes}{other} += $self->{n_nodes}{$subset};
            foreach my $compared_zone_label (@compared_zones_labels) {
                $self->{stats}{other}{$compared_zone_label}{correct} += $self->{stats}{$subset}{$compared_zone_label}{correct};
                $self->{stats}{other}{$compared_zone_label}{total} += $self->{stats}{$subset}{$compared_zone_label}{total};
            }
            next;
        }

        if ($subset eq 'other') {
            next;
        }

        $self->print_one_line($subset);

        if ($subset eq 'total') {
            print $border;
        }
    }

    print $border;
    $self->print_one_line('other');
    print $border;

    print "\n";
}

sub print_one_line {
    my ($self, $subset) = @_;

    my @compared_zones_labels = map { $_->get_label } @{$self->{compared_zones}};

    printf("%10s | ", $subset);
    printf("%10d | ", $self->{n_sentences}{$subset});
    printf("%10d | ", $self->{n_nodes}{$subset});
    printf("    %.4f | ", $self->{n_nodes}{$subset} / $self->{n_nodes}{total});
    foreach my $compared_zone_label (@compared_zones_labels) {
        my $accuracy = 0;
        if ($self->{stats}{$subset}{$compared_zone_label}{total} > 0) {
            $accuracy = $self->{stats}{$subset}{$compared_zone_label}{correct} / $self->{stats}{$subset}{$compared_zone_label}{total};
        }

        printf("     %.4f | ", $accuracy);
    }
    printf("\n");
}

sub process_end {
    my ($self) = @_;

    $self->print_stats();
}

1;

=over

=item Treex::Block::Clauses::CS::Eval

Evaluation of the dependency parsing, especially for parsing meta-algorithm by Kriz and Hladka (2016).
It takes selected zone as a gold-standard and calculates statistics for all other zones against this gold-standard.
Using option different_clasues=1 it reports UAS for all different clause structures.

=back

=cut

=head1 COPYRIGHT AND LICENSE

Copyright © 2016 by Vincent Kriz <kriz@ufal.mff.cuni.cz>

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
