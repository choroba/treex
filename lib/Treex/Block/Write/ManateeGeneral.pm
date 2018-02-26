package Treex::Block::Write::ManateeGeneral;

use strict;
use warnings;
use Moose;
use Treex::Core::Common;
use Treex::Tool::Lexicon::CS;

extends 'Treex::Block::Write::BaseTextWriter';

has '+language'                        => ( required => 1 );
has 'randomly_select_sentences_ratio'  => ( is       => 'rw', isa => 'Num',  default => 1 );
has 'is_member_within_afun'            => ( is       => 'rw', isa => 'Bool', default => 0 );
has 'is_shared_modifier_within_afun'   => ( is       => 'rw', isa => 'Bool', default => 0 );
has 'is_coord_conjunction_within_afun' => ( is       => 'rw', isa => 'Bool', default => 0 );
has 'get_bundle' => ( is       => 'rw', isa => 'Bool', default => 0 );
has '+extension' => ( default => '.vert' );
has 'attr_names' => ( is => 'rw', isa => 'Str', default => '');
has 'format'     => ( is => 'ro', isa => 'Str', default => '');

my %formats = (
  'UD1.3' => 'form lemma pos ufeatures deprel p_form p_lemma p_pos p_ufeatures p_afun parent',
  'styx1.0_input' => 'ord form lemma tag afun head school_deprel school_head',
  'styx1.0' => 'form lemma tag ord school_deprel school_parent school_head school_p_form school_p_lemma school_p_tag afun parent p_ord p_form p_lemma p_tag',
);

our %attributes;
our @attributes;

sub process_atree {
  my ( $self, $atree ) = @_;

  # if only random sentences are printed
  return if rand() > $self->randomly_select_sentences_ratio;
	
  foreach my $anode ( $atree->get_descendants( { ordered => 1 } ) ) {
    my @values;
    foreach (@attributes) {
      push @values, $self->get_attribute ($anode, $_);
	 }

    # Make sure that values are not empty 
    # values may contain whitespace if it is surrounded by non-whitespace
    @values = map {
      my $x = $_ // '_';  ## // is || but testing definedness instead of truth
      $x =~ s/^\s+//;
      $x =~ s/\s+$//;
      $x = '_' if ($x eq '');
      $x
    } (@values);
    print { $self->_file_handle } join( "\t", @values ) . "\n";
  }
  return;
}

#calculate distance from parent - UCNK style
sub calc_distance{
  my ($anode, $anode2ord) = @_;
  my $dist;
  if ( $anode2ord == '0' ){
    $dist = '0 but true';
  } else {
    $dist = $anode2ord - $anode->ord;
    if ($dist > 0){ $dist= '+'.$dist; }
  }
  return $dist;
}

sub get_attribute {
  my ( $self, $anode, $name ) = @_;
  my $value;
  if ($name eq 'a_type') {
    if ( $anode->get_referencing_nodes('a/lex.rf') ){
     $value = 'lex';
    } elsif ( $anode->get_referencing_nodes('a/aux.rf') ){
     $value = 'aux';
    } else {
     $value = 'null';
    }
  } elsif ($name eq 'deprel' or $name eq 'afun') {   ## depending on global config, add suffixes do deprel
    $value = $anode->get_attr($name);
    my $suffix = '';
    $suffix .= 'M' if $self->is_member_within_afun      && $anode->is_member;
    $suffix .= 'S' if $self->is_shared_modifier_within_afun  && $anode->is_shared_modifier;
    $suffix .= 'C' if $self->is_coord_conjunction_within_afun && $anode->wild->{is_coord_conjunction};
    $value .= "_$suffix" if $suffix;
  } elsif ($name eq 'ord' ) {
    $value = $anode->ord();
  } elsif ( $name eq 'pos' and !eval{$anode->wild->pos} ) {
    $value = $anode->tag;
  } elsif ($name eq 'ufeatures') {
    $value = join('|', $anode->iset()->get_ufeatures()); 

  ### now the fun part: extracting attributes of parent and effective parents
  } elsif ( $name =~ m/^e?parent$/ ) {    # parent, eparent -> relative distance (use p_ord for absolute value)
    my $function = "get_$name";
    $value = calc_distance($anode,$anode->$function->ord())+0;
  } elsif ( $name =~ m/^p_/ ) {           # attributes of a parent
    (my $attrname = $name) =~ s/^p_//;
    $value = get_attribute($self,$anode->get_parent,$attrname);
  } elsif ( $name =~ m/^ep_/ ) {
    (my $attrname = $name) =~ s/^ep_//;
    $value = get_attribute($self,$anode->get_eparent,$attrname);
  } elsif ( $name =~ m/_head$/  ) {     # e.g. school_parent
    $value = $anode->wild->{$name}->{head};
  } elsif ( $name =~ m/_parent$/  ) {     # e.g. school_parent
      eval { $value = $anode->get_attr($name) } or
      eval {  # e.g. we want school_parent and we know school_head
        (my $prefix = $name) =~ s/_parent$//; 
        if ((my $head = $anode->wild->{$prefix."_head"}->{head}) =~ m/^\d*$/) {
		    $value = calc_distance($anode,$anode->wild->{$prefix."_head"}->{head});
		  }
      } or
      $value = '_';
      if ($value eq '0 but true') {$value = $value + 0;}  ## convert to number 0
  } elsif ( $name =~ m/_p_/ ) {           # e.g. attributes of a school_parent
    (my $attrprefix = $name) =~ s/_p_.*//;
    (my $attrsufix = $name) =~ s/.*_p_//;
    if (exists($anode->wild->{$attrprefix."_head"}->{parent})) {
      $value = get_attribute($self,$anode->wild->{$attrprefix."_head"}->{parent},$attrsufix);
#    } elsif (exists($anode->wild->{$attrprefix."_head"}->{head}) && $anode->wild->{$attrprefix."_head"}->{head} eq "0") {
#      $value = "ROOT";
    }
  ### all other attributes
  } else {
    $value = eval {$anode->get_attr($name)} || 
             eval {$anode->get_attr($name.'_attribute')} ||   ###???? what does this do?
             eval {$anode->wild->{$name}} || 
             '_';    ## backup value if we do not find the value in any of the expected places
  }

  if ($self->language =~ 'cs|CS') {   ## convert lemmas to their basic form
    if ($name eq 'lemma' || $name eq 'p_lemma') {
      $value = Treex::Tool::Lexicon::CS::truncate_lemma( $value, 1 );
    }
  } 
 
  return ($value // '_');
}


override 'process_bundle' => sub {
  bt;
  my ($self, $bundle) = @_;  
  my $position = $bundle->id; #$bundle->get_position()+1;
  my $unique_id = $self->{file_stem} . "_" . $position;
  print { $self->_file_handle } "<s id=\"" . $unique_id . "\">\n";
  $self->SUPER::process_bundle($bundle);  
  print { $self->_file_handle } "</s>\n";
};

override 'print_header' => sub {
  my ($self, $document) = @_;
  $self->{file_stem} = $document->file_stem;
  my $metadata = $document->wild->{genre};
  $metadata = $metadata ? "genre=\"$metadata\"" : "";
  print { $self->_file_handle } "<doc id=\"".$document->file_stem."\" $metadata>\n";     

  ## set up the expected output format
  ## TODO: do this just once for all documents
  if ($self->format) {  ## if the format parameter is set, it overrides attr_names
    $self -> set_attr_names($formats{$self->format});
  }
  @attributes = split(/ /, $self->attr_names);
  %attributes = map { $_ => 1 } @attributes;
};

override 'print_footer' => sub {
  my ($self, $document) = @_;  
  print { $self->_file_handle } "</doc>\n";  
};

1;

__END__

=encoding utf8
=head1 NAME

Treex::Block::Write::ManateeGeneral

=head1 DESCRIPTION

Document writer for Manatee format, file with the following structure:

    <doc id="abc">
    <s id="1">
        tab-separated attributes of token1 in the order implied by parameter format or attr_names
        tab-separated attributes of token2 in the order implied by parameter format or attr_names
        ...
    </s>
    <s id="2">
        tab-separated attributes of token1 in the order implied by parameter format or attr_names
        ...
    </s>
    ...
    </doc>

=head1 PARAMETERS

=over

=item attr_names
Space separated list of token attributes that should be output, e.g.
form lemma tag ord school_deprel school_parent school_head school_p_form school_p_lemma school_p_tag afun parent p_ord p_form p_lemma p_tag
See %format for additional examples.
Values that cannot be found in the data structure are replaced with an underscore "_".

The following attribute names have special meaning:

C<parent>, resp. C<.*_parent>    
if attribute of the given name is not found, 
but C<head>, resp. C<.*_head> with the same prefix, is found,
the relative value to the parent is calculated.
A '+' sign is prefixed to positive values.
If C<head> has value 0, then C<parent> also has value 0 (marking of root node).

C<p_.*>, resp. C<.*_p_.*>, e.g. C<p_tag>, C<school_p_lemma>
Extract attribute C<.*> from the node's parent (as implied by C<head>),
resp. from the node implied by the value of C<.*_head>.

C<a_type>
has values C<lex>, C<aux> and C<null> depending on whether the given a-level node is 
a lexical/auxiliary reference of a t-layer node or not.


=item encoding

Output encoding. C<utf8> by default.

=item to

Space-or-comma-separated list of output file names, STDOUT by default.
If multiple documents are read and only one output file given in the C<to> parameter,
all input documents will be appended to a single file.


=item C<compress>

If set to 1, the output files are compressed using GZip (if C<to> is used to set
file names, the names must also contain the ".gz" suffix).=back
=item C<is_member_within_afun>, C<is_shared_modifier_within_afun>, C<is_coord_conjunction_within_afun>
Boolean; if true, append suffix C<_M>/C<_S>/C<_C> to the value of deprel and/or afun.
Default: false.

=head1 AUTHOR

Anna Vernerová <vernerova@ufal.mff.cuni.cz>

based on code by Ondřej Dušek, Michal Jozífko, Natalia Klyueva, David Mareček, Martin Popel, Daniel Zeman

=head1 COPYRIGHT AND LICENSE

Copyright © 2018 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
