package Treex::Block::Write::PDT;
use Moose;
use Treex::Core::Common;
use XML::Tidy;   ## in fact only use if pretty_print is true, but anyway

extends 'Treex::Block::Write::BaseTextWriter';

has '+compress' => (default=>1);

has 'version' => (isa => 'Str', is => 'ro', default => '2.0');

has 'vallex_filename' => ( isa => 'Str', is => 'rw', default => 'vallex.xml' );

has 'pretty_print' => ( isa => 'Bool', is => 'ro', default => 1 );

sub _build_to {return '.';} # BaseTextWriter defaults to STDOUT

my ($w_fh, $m_fh, $a_fh, $t_fh);
my ($w_fn, $m_fn, $a_fn, $t_fn);

sub process_document{
    my ($self, $doc) = @_;
    $self->{extension} = '.w';
    $w_fn = $self->_get_filename($doc);
    $w_fh = $self->_open_file_handle($w_fn);
    my $print_fn = $w_fn;
    $print_fn =~ s/.w(.gz|)$/.[wamt]$1/;
    log_info "Saving to $print_fn";
    # all [wamt] files are stored in the same directory - there should be no directory in relative paths
    $w_fn = $doc->file_stem . $self->_document_extension($doc);


    $self->{extension} = '.m';
    $m_fn = $self->_get_filename($doc);
    $m_fh = $self->_open_file_handle($m_fn);
    $m_fn = $doc->file_stem . $self->_document_extension($doc);

    $self->{extension} = '.a';
    $a_fn = $self->_get_filename($doc);
    $a_fh = $self->_open_file_handle($a_fn);
    $a_fn = $doc->file_stem . $self->_document_extension($doc);

    $self->{extension} = '.t';
    $t_fn = $self->_get_filename($doc);
    $t_fh = $self->_open_file_handle($t_fn);

    my $version_flag = "";
    if ($self->version eq "3.0") {
        $version_flag = "_30";
    } elsif ($self->version eq "3.5") {
        $version_flag = "_35";
    }

    my $doc_id = $doc->file_stem . $doc->file_number;
    my $lang   = $self->language;
    my $vallex_name = $self->vallex_filename;
    print {$w_fh} << "END";
<?xml version="1.0" encoding="utf-8"?>
<wdata xmlns="http://ufal.mff.cuni.cz/pdt/pml/">
<head><schema href="wdata$version_flag\_schema.xml"/></head>
<meta><original_format>treex</original_format></meta>
<doc id="$doc_id">
<docmeta/>
<para>
END
    print {$m_fh} << "END";
<?xml version="1.0" encoding="utf-8"?>
<mdata xmlns="http://ufal.mff.cuni.cz/pdt/pml/">
<head>
  <schema href="mdata$version_flag\_schema.xml" />
  <references>
    <reffile id="w" name="wdata" href="$w_fn" />
  </references>
</head>
<meta><lang>$lang</lang></meta>
END
    print {$a_fh} << "END";
<?xml version="1.0" encoding="utf-8"?>
<adata xmlns="http://ufal.mff.cuni.cz/pdt/pml/">
<head>
  <schema href="adata$version_flag\_schema.xml" />
  <references>
   <reffile id="m" name="mdata" href="$m_fn" />
   <reffile id="w" name="wdata" href="$w_fn" />
  </references>
</head>
<trees>
END
    print {$t_fh} << "END";
<?xml version="1.0" encoding="utf-8"?>
<tdata xmlns="http://ufal.mff.cuni.cz/pdt/pml/">
<head>
  <schema href="tdata$version_flag\_schema.xml" />
  <references>
   <reffile id="a" name="adata" href="$a_fn" />
   <reffile id="v" name="vallex" href="$vallex_name" />
  </references>
</head>
<trees>
END

    $self->Treex::Core::Block::process_document($doc);

    print {$w_fh} "</para>\n</doc>\n</wdata>";
    print {$m_fh} "</mdata>";
    print {$a_fh} "</trees>\n</adata>";
    print {$t_fh} "</trees>\n</tdata>";
    foreach my $fh ($w_fh,$m_fh,$a_fh,$t_fh) {close $fh;}
    if ($self->pretty_print) {
      foreach my $fn (split /\s+/, $self->to) {
        my $tidy_obj = XML::Tidy->new('filename' => "$fn");
        $tidy_obj->tidy();
        $tidy_obj->write();
      }
    }
    return;
}

sub escape_xml {
    my ($self, $string) = @_;
    return if !defined $string;
    $string =~ s/&/&amp;/;
    $string =~ s/</&lt;/;
    $string =~ s/>/&gt;/;
    $string =~ s/'/&apos;/;
    $string =~ s/"/&quot;/;
    return $string;
}

sub process_atree {
    my ($self, $atree) = @_;
    ( my $s_id = $atree->id ) =~ s/^a-//;
    print {$m_fh} "<s id='m-$s_id'>\n";
    foreach my $anode ($atree->get_descendants({ordered=>1})){
        my ($id, $form, $lemma, $tag) = map{$self->escape_xml($_)} $anode->get_attrs(qw(id form lemma tag), {undefs=>'?'});
        my $nsa = $anode->no_space_after ? '<no_space_after>1</no_space_after>' : '';
        ( my $w_id = $id ) =~ s/^a-/w-/;
        ( my $m_id = $id ) =~ s/^a-/m-/;
        print {$w_fh} "<w id='$w_id'><token>$form</token>$nsa</w>\n";
        print {$m_fh} "<m id='$m_id'><w.rf>w#$w_id</w.rf><form>$form</form><lemma>$lemma</lemma><tag>$tag</tag></m>\n";
    }
    print {$m_fh} "</s>\n";
    print {$a_fh} "<LM id='a-$s_id'><s.rf>m#m-$s_id</s.rf><ord>0</ord>\n<children>\n";
    foreach my $child ($atree->get_children()) { $self->print_asubtree($child); }
    print {$a_fh} "</children>\n</LM>\n";
    return;
}

sub print_asubtree {
    my ($self, $anode) = @_;
    my ($a_id, $afun, $ord) = $anode->get_attrs(qw(id afun ord));
    $a_id = 'missingID-'.rand(1000000) if !defined $a_id;
    ( my $m_id = $a_id ) =~ s/^a-/m-/;
    $afun = '???' if !defined $afun;
    $ord = 0 if !defined $ord;
    print {$a_fh} "<LM id='$a_id'><m.rf>m#$m_id</m.rf><afun>$afun</afun><ord>$ord</ord>";
    print {$a_fh} '<is_member>1</is_member>' if $anode->is_member;
    print {$a_fh} '<is_parenthesis_root>1</is_parenthesis_root>' if $anode->is_parenthesis_root;
    if (my @children = $anode->get_children()){
        print {$a_fh} "\n<children>\n";
        foreach my $child (@children) { $self->print_asubtree($child); }
        print {$a_fh} "</children>\n";
    }
    print {$a_fh} "</LM>\n";
    return;
}

sub process_ttree {
    my ($self, $ttree) = @_;
    my $s_id = $ttree->id;
    my $a_s_id = $ttree->get_attr('atree.rf');
    if (!$a_s_id){
        ( $a_s_id = $s_id ) =~ s/^t-/a-/;
        $a_s_id =~ s/t_tree/a_tree/;
    }
    print {$t_fh} "<LM id='$s_id'><atree.rf>a#$a_s_id</atree.rf><deepord>0</deepord>\n<children>\n";
    foreach my $child ($ttree->get_children()) { $self->print_tsubtree($child); }
    print {$t_fh} "</children>\n</LM>\n";
    return;
}

sub print_tsubtree {
    my ($self, $tnode) = @_;
    my ($id, $ord) = $tnode->get_attrs(qw(id ord), {undefs=>'?'});
    print {$t_fh} "<LM id='$id'>";

    # references
    my $lex = $tnode->get_lex_anode();
    my @aux = $tnode->get_aux_anodes();
    if ($lex || @aux){
        print {$t_fh} "<a>";
        printf {$t_fh} "<lex.rf>a#%s</lex.rf>", $lex->id if $lex;
        if (@aux==1){
            printf {$t_fh} "<aux.rf>a#%s</aux.rf>", $aux[0]->id;
        }
        if (@aux>1){
            print {$t_fh} "<aux.rf>";
            printf {$t_fh} "<LM>a#%s</LM>", $_->id for @aux;
            print {$t_fh} "</aux.rf>";
        }
        print {$t_fh} "</a>\n";
    }

    # simple attrs, part 1
    foreach my $attr (qw(nodetype)){
        my $val = $self->escape_xml($tnode->get_attr($attr));
        $val = 'RSTR' if $attr eq 'functor' and (!$val or $val eq '???'); #TODO functor is required in PDT
        print {$t_fh} "<$attr>$val</$attr>" if defined $val;
    }

    # boolean attrs, part 1
    foreach my $attr (qw(is_generated)){
        print {$t_fh} "<$attr>1</$attr>" if $tnode->get_attr($attr);
    }

    # simple attrs, part 1b
    foreach my $attr (qw(t_lemma functor subfunctor sentmod)){
        my $val = $self->escape_xml($tnode->get_attr($attr));
        $val = 'RSTR' if $attr eq 'functor' and (!$val or $val eq '???'); #TODO functor is required in PDT
        print {$t_fh} "<$attr>$val</$attr>" if defined $val;
    }

    # boolean attrs, part 2
    foreach my $attr (qw(is_dsp_root is_member is_name_of_person is_parenthesis is_state)){
        print {$t_fh} "<$attr>1</$attr>" if $tnode->get_attr($attr);
    }

    # list attrs, part 1
    foreach my $attr (qw(compl.rf)){
        my @antes = $tnode->_get_node_list($attr);
        if (@antes) {
            print {$t_fh} "<$attr>";
            foreach my $ante (@antes) {
                my $ante_id = $ante->id;
                print {$t_fh} "<LM>t-$ante_id</LM>";
            }
            print {$t_fh} "</$attr>";
        }
    }


    # discourse
    my $ref_discourse_arrows = $tnode->get_attr('discourse');
    my @discourse_arrows = ();
    if ($ref_discourse_arrows) {
        @discourse_arrows = @{$ref_discourse_arrows};
    }
    if (@discourse_arrows) {
        print {$t_fh} "<discourse>";
        foreach my $arrow (@discourse_arrows) { # take all discourse arrows starting at the given node
            # simple attrs
            # foreach my $attr (qw(target_node.rf type start_group_id start_range target_group_id target_range discourse_type is_negated comment src is_altlex is_compositional connective_inserted is_implicit is_NP)) {
            foreach my $attr (qw(target_node.rf type start_group_id start_range target_group_id target_range discourse_type is_negated comment is_altlex is_compositional connective_inserted is_implicit is_NP)) {
                my $val = $self->escape_xml($arrow->{$attr});
                if ($attr eq 'target_node.rf') {
                  $val = "t-$val";
                }
                print {$t_fh} "<$attr>$val</$attr>" if defined $val;
            }
            # list attrs
            foreach my $attr (qw(a-connectors.rf t-connectors.rf a-connectors_ext.rf t-connectors_ext.rf)) {
                my $ref_target_ids = $arrow->{$attr};
                my @target_ids = ();
                if ($ref_target_ids) {
                    @target_ids = @{$ref_target_ids};
                }
                if (@target_ids) {
                    print {$t_fh} "<$attr>";
                    foreach my $target_id (@target_ids) {
                        my $prefix = "t-";
                        if ($attr =~ /^a-/) {
                          $prefix = "a-";
                        }
                        print {$t_fh} "<LM>$prefix$target_id</LM>";
                    }
                    print {$t_fh} "</$attr>";
                }
            }
        }
        print {$t_fh} "</discourse>";
    }

    # grammatemes
    { my $already_printed = 0;
    foreach my $attr (qw(sempos gender number numertype typgroup degcmp verbmod deontmod tense aspect resultative dispmod iterativeness indeftype person politeness negation diatgram factmod )){ # definiteness diathesis
        my $val = $tnode->get_attr("gram/$attr") // '';
        unless ($self->version eq "3.5") { #TODO sempos is required in PDT
          $val = 'n.denot' if !$val and $attr eq 'sempos';
        }
        if ($self->version eq "3.0" or $self->version eq "3.5") { # grammatemes dispmod and resultative have been canceled, verbmod changed to factmod, and diatgram has been introduced (here ignoring diatgram for now)
            next if ($attr =~ /^(dispmod|resultative)$/);
            if ($attr eq 'verbmod') {
                my $factmod;
                $factmod = 'asserted' if ($val eq 'ind');
                $factmod = 'appeal' if ($val eq 'imp');
                $factmod = 'nil' if ($val =~ /^(nr|nil)$/);
                if ($val eq 'cdn') {
                    my $tense = $tnode->get_attr("gram/tense") // '';
                    $factmod = $tense eq 'ant' ? 'irreal' : 'potential';
                }
                if ( defined $factmod and not $already_printed) {
                  print {$t_fh} "<gram>";
                  $already_printed = 1;
                }
                print {$t_fh} "<factmod>$factmod</factmod>" if defined $factmod;
                next;
            }
            elsif ($attr eq 'tense') {
                my $verbmod = $tnode->get_attr("gram/verbmod") // '';
                if ($verbmod eq 'cdn') { # in PDT 3.0, tense is set to 'nil' in case of factmod values 'irreal' and 'potential' (i.e. originally in PDT 2.0 'cdn' in vebmod)
                    unless ($already_printed) {
                      print {$t_fh} "<gram>";
                      $already_printed = 1;
                    }
                    print {$t_fh} "<tense>nil</tense>";
                    next;
                }
            }
        }
        if ($val and not $already_printed) {
          print {$t_fh} "<gram>";
          $already_printed = 1;
        }
        print {$t_fh} "<$attr>$val</$attr>" if $val;
    }
    print {$t_fh} "</gram>\n" if $already_printed;
    $already_printed = 0;
    }

    # simple attrs, part 2 - tfa
    foreach my $attr (qw(coref_special tfa)){
        my $val = $self->escape_xml($tnode->get_attr($attr));
        $val = 'RSTR' if $attr eq 'functor' and (!$val or $val eq '???'); #TODO functor is required in PDT
        print {$t_fh} "<$attr>$val</$attr>" if defined $val;
    }


	# deepord
    print {$t_fh} "<deepord>$ord</deepord>";

    # list attrs, part 2
    foreach my $attr (qw(coref_gram.rf)){
        my @antes = $tnode->_get_node_list($attr);
        if (@antes) {
            print {$t_fh} "<$attr>";
            foreach my $ante (@antes) {
                my $ante_id = $ante->id;
                print {$t_fh} "<LM>t-$ante_id</LM>";
            }
            print {$t_fh} "</$attr>";
        }
    }


    # bridging
    my $ref_arrows = $tnode->get_attr('bridging');
    my @arrows = ();
    if ($ref_arrows) {
        @arrows = @{$ref_arrows};
    }
    if (@arrows) {
        print {$t_fh} "<bridging>";
        foreach my $arrow (@arrows) { # take all bridging arrows starting at the given node
            # simple attrs
            # foreach my $attr (qw(target_node.rf type comment src)) {
            foreach my $attr (qw(target_node.rf type comment)) {
                my $val = $self->escape_xml($arrow->{$attr});
                if ($attr eq 'target_node.rf') {
                  $val = "t-$val";
                }
                print {$t_fh} "<$attr>$val</$attr>" if defined $val;
            }
        }
        print {$t_fh} "</bridging>";
    }


    # coref text
    my @antes = $tnode->get_coref_text_nodes();
    if (@antes) {
        if ($self->version eq "3.0" or $self->version eq "3.5") {
            print {$t_fh} "<coref_text>";
            foreach my $ante (@antes) {
                my $ante_id = $ante->id;
                print {$t_fh} "<LM><target_node.rf>$ante_id</target_node.rf><type>SPEC</type></LM>";
            }
            print {$t_fh} "</coref_text>";
        }
        else {
            print {$t_fh} "<coref_text.rf>";
            foreach my $ante (@antes) {
                my $ante_id = $ante->id;
                print {$t_fh} "<LM>$ante_id</LM>";
            }
            print {$t_fh} "</coref_text.rf>";
        }
    }

    # simple attrs, part 3 - discourse, valency
    foreach my $attr (qw(discourse_special val_frame.rf)){
        my $val = $self->escape_xml($tnode->get_attr($attr));
        $val = 'RSTR' if $attr eq 'functor' and (!$val or $val eq '???'); #TODO functor is required in PDT
        print {$t_fh} "<$attr>$val</$attr>" if defined $val;
    }



    # recursive children
    if (my @children = $tnode->get_children()){
        print {$t_fh} "\n<children>\n";
        foreach my $child (@children) { $self->print_tsubtree($child); }
        print {$t_fh} "</children>\n";
    }
    print {$t_fh} "</LM>\n";
    return;
}

1;

__END__

=encoding utf-8

=head1 NAME

Treex::Block::Write::PDT - save *.w,*.m,*.a,*.t files

=head1 SYNOPSIS

 # convert *.treex files to *.w.gz,*.m.gz,*.a.gz,*.t.gz
 treex Write::PDT -- *.treex

 # convert *.treex.gz files to *.w,*.m,*.a,*.t
 treex Write::PDT compress=0 -- *.treex.gz

=head1 DESCRIPTION

Save Treex documents in PDT style PML files.

=head1 TODO

You can try reimplement this using Treex::PML if you dare.

is_member should be moved from AuxC/AuxP down (Treex vs. PDT style).

add t-layer attribute "quot"

Check links to Vallex (val_frame.rf)

(2. 9. 2018): the follwing attributes are not converted properly by the simple roundabout scenario
treex -Lcs Read::PDT from="input/tamw/train-1/ln94200_2.t.gz" Write::PDT to="out.w out.m out.a out.t" version=3.5 compress=0

w-layer: <para>, <othermarkup>, <docmeta>, <othermeta>, <original_format>
m-layer: <annotation_info>, <src.rf>, <LM>
a-layer: <meta>, <clause_number>
         order of <ord> and <is_member>
t-layer: <meta>, <mwes>
         some EXTRA coref_text links, they seem to be present in the structure obtained from Read::PDT, but I cannot understand why


=head1 AUTHOR

Martin Popel <popel@ufal.mff.cuni.cz>
Jiri Mirovsky <mirovsky@ufal.mff.cuni.cz> (bridging and discourse related parts)

=head1 COPYRIGHT AND LICENSE

Copyright © 2012-2016 by Institute of Formal and Applied Linguistics, Charles University in Prague

This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself.
