
use strict;
use warnings;

package CXGN::Phenome::Stock::StockForm;
my $stock_form = CXGN::Phenome::Stock::StockForm->new();

use base qw/CXGN::Page::Form::AjaxFormPage  /; 


use CXGN::Tools::Organism;
use Bio::Chado::Schema;
use CXGN::Chado::Stock;

use CXGN::People::Person;
use CXGN::Contact; 


use Try::Tiny;

use JSON;
use CatalystX::GlobalContext qw( $c );


sub new {
    my $class  = shift;
    my $self   = $class->SUPER::new(@_);
    return $self;
}

sub define_object {
    my $self = shift;
    my %args      = $self->get_args();
    my $stock_id  = $args{stock_id} || $args{object_id};
    my $user_type = $self->get_user()->get_user_type();
    my %json_hash= $self->get_json_hash();
   
    my $schema   = $c->dbic_schema( 'Bio::Chado::Schema', 'sgn_chado' );
    
    $self->set_object_id($stock_id);
    $self->set_object_name('Stock'); #this is useful for email messages
    $self->set_object( CXGN::Chado::Stock->new($schema, $stock_id) );
    
    if ( $self->get_object()->get_obsolete() eq 't' && $user_type ne 'curator' )
    {
	$json_hash{error}="Stock $stock_id is obsolete!";
    }
    unless ( ( $stock_id =~ m /^\d+$/ || !$stock_id  )  ) {
       	$json_hash{error}="No stock exists for identifier $stock_id";
    }
    $self->set_json_hash(%json_hash);
    $self->set_primary_key("stock_id");
    my @owners;
    #my @owners = $self->get_object()->search_related("stockprops", { 
    #type_id => $sp_person_cvterm_id } );
    
    $self->set_owners( @owners );
    
    $self->print_json() if $json_hash{error};
}


sub store {
    my $self=shift;
    
    my $stock    = $self->get_object();
    my $stock_id = $self->get_object_id();
    my %args     = $self->get_args();
    my %json_hash = $self->get_json_hash();
    my $initial_stock_id = $stock_id;
   
    my $error;
    $stock->organism_id($args{organism_id});
    
    my ($message) ;
	#$locus->exists_in_database( $args{locus_name}, $args{locus_symbol} );
    my $validate;
    if ($message) {
	$error = " Stock $args{stock_name}  already exists in the database ";
    }else {
	try{
	    $self->SUPER::store(); #this sets $json_hash{validate} if the form validation failed.
	    $stock_id = $stock->get_stock_id() ;
	} catch { 
	    $error = " An error occurred. Cannot store to the database\n An  email message has been sent to the SGN development team";
	    CXGN::Contact::send_email('stock_ajax_form.pl died', $error . "\n" . $_ , 'sgn-bugs@sgn.cornell.edu');
	};
    }
    #the validate field is false is validation passed for all fields, true if did not pass and the form is re-printed
    #$json_hash{validate}= $validate;
    %json_hash= $self->get_json_hash();
    $validate= $json_hash{validate};
    $json_hash{error} = $error if $error;
    
    my $refering_page="/phenome/stock.pl?stock_id=$stock_id";
    $self->send_form_email({subject=>"[New stock details stored] stock $stock_id", mailing_list=>'sgn-db-curation@sgn.cornell.edu', refering_page=>"www.solgenomics.net".$refering_page}) if (!$validate && !$json_hash{error});
    $json_hash{refering_page}=$refering_page if !$initial_stock_id && !$validate && !$error;
    
    $self->set_json_hash(%json_hash);
    
    $self->print_json();
}


####################################
sub delete {
    ##Delete the stock (actually set obsolete = 't')
    my $self = shift;
    my $check = $self->check_modify_privileges();
    $self->print_json() if $check ; #error or no user privileges
    
    my $stock      = $self->get_object();
    my $stock_name = $stock->name();
    my $stock_id = $stock->stock_id();
    my %json_hash= $self->get_json_hash();
    my $refering_page="/phenome/stock.pl?stock_id=$stock_id";
    
    if (!$json_hash{error} ) {
	try {
	    $stock->create_stockprops( { obsolete => 1 } , {autocreate=> 1 } );
	}catch {
	    $json_hash{error} = " An error occurred. Cannot delete stock\n An  email message has been sent to the SGN development team";
	};
	$json_hash{reload} = 1;
    }
    $self->send_form_email({subject=>"Stock obsoleted ($stock_name)", mailing_list=>'sgn-db-curation@sgn.cornell.edu', refering_page=>"www.solgenomics.net".$refering_page, action=>'delete'}) if (!$json_hash{error});
    $self->set_json_hash(%json_hash);
    $self->print_json();
}



sub generate_form {
    my $self = shift;
    my $form_id = 'edit_stock'; # a form_id is required for ajax forms
    
    $self->init_form($form_id) ; ## instantiate static/editable/confirmStore form
    my $stock = $self->get_object();
    my $bcs_stock = $stock->get_object_row();
    my %args  = $self->get_args();
    my $form = $self->get_form();
    my $dbh = $self->get_dbh();
   
    #########
    my ( $organism_names_ref, $organism_ids_ref ) =
	CXGN::Tools::Organism::get_all_organisms( $self->get_dbh() );
    my ($web_visible) = $stock->get_schema->resultset("Cv::Cvterm")->search(
	{ name => 'web visible' , }
	);
    my @species;
    my @organism_ids;
    if ($web_visible) {
	my $organism_res = $stock->get_schema->resultset("Organism::Organismprop")->
	    search( { type_id => $web_visible->cvterm_id(), } )->
	    search_related('organism');
	while (my $o = $organism_res->next() ) {
	    push @species, $o->species() ;
	    push @organism_ids, $o->organism_id();
	}
    }
    
    ##########

    if ( $self->get_action =~ /new|store/ ) {
	$self->get_form->add_select(
	    display_name       => "Organism ",
	    field_name         => "organism_id",
	    contents           => $bcs_stock->organism_id(),
	    length             => 20,
	    object             => $bcs_stock,
	    getter             => "organism_id",
	    setter             => "organism_id",
	    select_list_ref    => \@species,
	    select_id_list_ref => \@organism_ids,
	    );
	
    }
    if ( $stock->get_obsolete() eq 't' ) {
	$form->add_label(
	    display_name => "Status",
	    field_name   => "obsolete_stat",
	    contents     => 'OBSOLETE',
	    );
    }
    $form->add_label(
	display_name => "Organism ",
	field_name   => "stock_organism",
	contents => $bcs_stock->organism->species,
	);
    
	
    $form->add_field(
	display_name => "Stock name ",
	field_name   => "stock_name",
	object       => $bcs_stock,
	getter       => "name",
	setter       => "name",
	validate     => 'string',
	);
    $form->add_field(
	display_name => "Uniquename ",
	field_name   => "stock_uniquename",
	object       => $bcs_stock,
	getter       => "uniquename",
	setter       => "uniquename",
	validate     => 'string',
	);
    
    
    if ( $self->get_action() =~ /view|edit/ ) {
	$form->from_database();
	$form->add_hidden(
	    field_name => "organims_id",
	    contents   => $stock->get_object_row(),
	    );
	
    }
    elsif ( $self->get_action() =~ /store/ ) {
	$form->from_request( %args );
    }
}



1;
