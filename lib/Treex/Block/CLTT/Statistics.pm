package Treex::Block::CLTT::Statistics;

## Vincent Kriz, 2017
## Retokenizuje reference na pravni dokumnety.

use Moose;
use Treex::Core::Common;

extends 'Treex::Core::Block';


sub process_atree {
    my ($self, $aroot) = @_;

    my @children = $aroot->get_descendants();
    my $n_children = scalar(@children);

    if (scalar(@children) == 0) {
        log_error('Empty sentence: ' . $aroot);
    }

    $self->{tokens} += $n_children;
    $self->{sentence_length}{$n_children} += 1;
}

sub process_end {
    my ($self) = @_;
    my @groups = (0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 1000);

    print "\n\n";
    print "# of tokens = $self->{tokens}\n";

    print "\n\n";
    print "Sentence Length Distribution\n\n\n";
    my $total_sum = 0;
    for (my $i = 1; $i < scalar(@groups); $i++) {
        my $sum = 0;
        foreach my $n_children (keys %{$self->{sentence_length}}) {
            if ($n_children > $groups[$i - 1] and $n_children <= $groups[$i]) {
                $sum += $self->{sentence_length}{$n_children};
            }
        }
        printf("%4d - %4d | %4d\n", $groups[$i - 1], $groups[$i], $sum);
        $total_sum += $sum;
    }
    printf("------------+-----\n");
    printf("            | %4d\n\n\n", $total_sum)
}

1;
