package Treex::Block::Read::CoNLLlike;

use warnings;
use Moose;
use Treex::Core::Common;
use feature qw(say);
use warnings FATAL => qw( all );

extends 'Treex::Block::Read::BaseCoNLLReader';

has 'doc_reset_sent_id' => ( is => 'ro', isa => 'Bool', default => 0 );
has 'use_p_attribs' => ( is => 'ro', isa => 'Bool', default => 0 );
has 'attr_names' => ( is => 'rw', isa => 'Str', default => '');
has 'format'     => ( is => 'ro', isa => 'Str', default => '');

use Devel::PrettyTrace; ## put "bt;" as the first command into any function you want to debug
#use Data::Printer alias => 'dump', colored => 1, indent => 2, escape_chars => "all", show_tied => 1, class => {internals => "1", inherited => 'none', expand => 'all', show_methods => "none"}, caller_info => 1;
use Data::Printer alias => 'dump', colored => 1, indent => 2, class => {internals => "1", inherited => 'none', expand => 1, show_methods => "none"}, caller_info => 1;
                               # similar to Data::Dumper, but with colourful output,
                               #    and numbering the array elements from 0
                               # the alias means that we can use the same function Dumper as with Data::Dumper
                               # without the alias, dumpt to STDERR
                               # do not use the alias together with Devel::PrettyTrace - it relies on Data::Printer calling the dumping function p()
#print p(@array, colored => 1); # now print to STDOUT 
                               #     - if you ask for a return value, it does not dump to STDERR
                               # with the colored option set already in "use Data::Printer",
                               #    it is not necessary to set colored to 1 even in "print p(...)"

# Debuging...
my $debug = 0;
sub _debug {
  #if ($debug) { say join "\n", @_; }
  if ($debug) { dump @_; }
}


our %attributes;
our $newnode;
sub also_set {
  my ($attr_name, $attr_value, $attr_to_set, $attr_to_get) = @_;
  #_debug($attr_name, $attr_value, $attr_to_set, $attr_to_get);
  if ( ($attr_name eq $attr_to_get) and (not(exists($attributes{$attr_to_set}))) ) {
    my $set = "set_$attr_to_set";
    if ($attr_to_set eq "ord") {$set = "_set_ord";}
    $newnode->$set($attr_value);
  }
}

my %formats = (
  "styx1.0" => "ord form lemma tag afun head school_deprel school_head",
);

sub next_document {
  my ($self) = @_;
  if ($self->format) {
    $self -> set_attr_names($formats{$self->format});
  }
  my @attributes = split(/ /, $self->attr_names);
  my %attributes = map { $_ => 1 } @attributes;

    my $text = $self->next_document_text();
    return if !defined $text;
    $self->set_sent_in_file(0) if ($self->doc_reset_sent_id);

    my $document = $self->new_document();
    foreach my $tree ( split /\n\s*\n/, $text ) {
        my @lines  = split( /\n/, $tree );

        # Skip empty sentences (if any sentence is empty at all,
        # typically it is the first or the last one because of superfluous empty lines).
        next unless(@lines);
        my $comment = '';
        my $bundle  = $document->create_bundle();
        # The default bundle id is something like "s1" where 1 is the number of the sentence.
        # If the input file is split to multiple Treex documents, it is the index of the sentence in the current output document.
        # But we want the input sentence number. If the Treex documents are later exported to one file again, the sentence ids should remain unique.
        # Note that this is only the default sentence id for files that do not contain their own sentence ids. If they do, it will be overwritten below.
        my $sentid = $self->sent_in_file() + 1;
        my $sid = $self->sid_prefix().'s'.$sentid;
        $bundle->set_id($sid);
        $self->set_sent_in_file($sentid);
        my $zone = $bundle->create_zone( $self->language, $self->selector );
        my $aroot = $zone->create_atree();
        $aroot->set_id($sid.'/'.$self->language());
        my @parents = (0);
        my @conll_parents = (0);
        my @nodes   = ($aroot);
        my $sentence;
        LINE:
        foreach my $line (@lines) {
            next LINE if $line =~ /^\s*$/;
            if ($line =~ s/^#\s*//)
            {
                # sent_id metadata sentence-level comment
                if ($line =~ m/^sent_id(?:\s*=\s*|\s+)(.*)/)
                {
                    my $sid = $1;
                    my $zid = $self->language();
                    # Some CoNLL-U files already have sentence ids with "/language" suffix while others don't.
                    if ($sid =~ s-/(.+)$--)
                    {
                        $zid = $1;
                    }
                    # Make sure that there are no additional slashes.
                    $sid =~ s-/.*$--;
                    $zid =~ s-/.*$--;
                    $bundle->set_id( $sid );
                    $aroot->set_id( "$sid/$zid" );
                }
                # text metadata sentence-level comment
                elsif ($line =~ m/^text\s*=\s*(.*)/)
                {
                    my $text = $1;
                    $zone->set_sentence($text);
                }
                # any other sentence-level comment
                else
                {
                    $comment .= "$line\n";
                }
                next LINE;
            }
            # Since UD v2, there may be lines with empty nodes of the enhanced representation.
            ###!!! Currently skip empty nodes!
            elsif ($line =~ m/^\d+\.\d+/)
            {
                next LINE;
            }
            # Since UD v2, the FORM and LEMMA columns may contain spaces, thus we can only use the TAB character as column separator.
            chomp($line); $line =~ s/\R//g;   ## also remove carriage returns;
            my @tokens = split( /\t/, $line );
            my $newnode = $aroot->create_child();
            $newnode->shift_after_subtree($aroot);
            foreach (@attributes) {
                my $attr_value = shift @tokens;
                ### special treatment of some attributes:
                ### default treatment: just assign the value from the file to the given attribute
                if ($_ eq "ord") {
                  $newnode->_set_ord($attr_value);
                } elsif ($_ eq "upos") {
                  $newnode->iset->set_upos($attr_value);
                } elsif ($_ eq "feats" and $attr_value ne '_') {
                  $newnode->iset->add_ufeatures(split(/\|/,$attr_value));
                } elsif ($_ eq "misc" and $attr_value ne '_') {
                  if ($attr_value =~ s/SpaceAfter=No// ) {
                    $newnode->set_no_space_after(1);
                  }
                  if ($attr_value =~ s/(^|\|)(Translit=[^\|]*)//g) {
                    $newnode->set_translit($2);
                  }
                  if ($attr_value =~ s/(^|\|)(LTranslit=[^\|]*)//g) {
                    $newnode->set_ltranslit($2);
                  }
                  if ($attr_value =~ s/(^|\|)(Gloss=[^\|]*)//g) {
                    $newnode->set_gloss($2);
                  }
                  ## after removing SpaceAfter=No, we have to remove extra | left behind
                  $attr_value =~ s/\|\|/\|/g; $attr_value =~ s/^\||\|$//;
                  my @misc = split(/\|/, $attr_value);
                  $newnode->set_misc(@misc);
                } elsif ($_ eq "head") {
                  push @parents, $attr_value;
                #} elsif ($_ eq "conll_head") {
                #  push @conll_parents, $attr_value;
                } elsif ( $_ =~ m/_head$/ ) {  
                   ## e.g. school_head; if we want to be able to extract school_p_lemma later, 
                   ## we have to store the parent node as part of the current node
                   $newnode->wild->{"$_"}->{"head"} = $attr_value;
                } else {
                  my $set = "set_$_";
                  eval {$newnode->$set($attr_value)} or $newnode->wild->{"$_"}=$attr_value;
                }
                # copy some values to similar attributes if not present in the file
                # e.g., Tred and PML-TQ should preferably display upos as the main tag of the node.
                also_set($_,$attr_value,"tag","upos");
                also_set($_,$attr_value,"conll_cpos","upos");
                also_set($_,$attr_value,"conll_pos","postag");
                also_set($_,$attr_value,"conll_feat","feats");
                also_set($_,$attr_value,"conll_deprel","deprel");
            }
            log_warn "Extra columns: '@tokens'" if $#tokens;

            if ($self->use_p_attribs) {
                $newnode->set_lemma($newnode->{"plemma"});
                $newnode->set_postag($newnode->{"ppos"});
                $newnode->set_feats($newnode->{"pfeat"});
                $newnode->set_head($newnode->{"phead"});
                $newnode->set_deprel($newnode->{"pdeprel"});
            }

            $sentence .= "$newnode->{'form'}";
            $sentence .= ' ' unless $newnode->no_space_after;
            push @nodes, $newnode;
        }
        if ($attributes{"head"}) {
          foreach my $i ( 1 .. $#nodes ) {
            $nodes[$i]->set_parent( $nodes[ $parents[$i] ] );
          }
        }
        foreach my $attrhead (grep(/_head$/, @attributes)) {   ##
          foreach my $i ( 1 .. $#nodes ) {
            if (exists($nodes[$i]->wild->{"$attrhead"}->{"head"}) && $nodes[$i]->wild->{"$attrhead"}->{"head"} =~ '^[1-9][0-9]*$') {
              $nodes[$i]->wild->{"$attrhead"}->{"parent"} = $nodes[$nodes[$i]->wild->{"$attrhead"}->{"head"}];
              _debug($nodes[$i]);
            }
          }
        }
        $sentence =~ s/\s+$//;
        $zone->set_sentence($sentence);
        $bundle->wild->{comment} = $comment;
    }

    return $document;
}

1;

__END__

=head1 NAME

Treex::Block::Read::CoNLLlike

=head1 DESCRIPTION

General document reader for files in CONLL-like formats.

Each token is on separate line with attributes in vertical tab-separated format;
the names of the attributes are provided through the parameter attr_names
Sentences are separated with blank line.
The sentences are stored into L<bundles|Treex::Core::Bundle> in the
L<document|Treex::Core::Document>.

=head1 ATTRIBUTES

=over

=item from

space or comma separated list of filenames

=item lines_per_doc

number of sentences (!) per document

=item attr_names

Space or comma separated list of names of attributes present in the input file 
( = names of columns ).

=back

=head1 METHODS

=over

=item next_document

Loads a document.

=back

=head1 SEE

L<Treex::Block::Read::BaseTextReader>
L<Treex::Core::Document>
L<Treex::Core::Bundle>

=head1 AUTHOR

Anna Vernerová <vernerova@ufal.mff.cuni.cz>
David Mareček <marecek@ufal.mff.cuni.cz>
Martin Popel <popel@ufal.mff.cuni.cz>
Dan Zeman <zeman@ufal.mff.cuni.cz>

=head1 COPYRIGHT AND LICENSE

Copyright © 2011-2018 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
