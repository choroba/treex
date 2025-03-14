package Treex::Tool::UMR::CS::GrammatemeSetter;
use Moose::Role;
with 'Treex::Tool::UMR::GrammatemeSetter';

use experimental qw{ signatures };

=head1 NAME

Treex::Tool::UMR::CS::GrammatemeSetter - Language specific grammateme
deduction from morphology.

=cut

{    my %REGEX = (person => '^.{7}([123])',
                 number => '^.{3}([SP])');
    sub tag_regex($self, $grammateme) { $REGEX{$grammateme} }
}

{   my %GRAM = (person => {1     => '1st',
                           2     => '2nd',
                           3     => '3rd'},
                number => {S     => 'singular',
                           P     => 'plural'});
    sub translate($self, $grammateme, $value) { $GRAM{$grammateme}{$value} }
}

__PACKAGE__
