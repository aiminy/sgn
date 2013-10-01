
package CXGN::List::Validate::Plugin::Plots;

use Moose;

sub name { 
    return "plots";
}

sub validate { 
    my $self = shift;
    my $c = shift;
    my $list = shift;

    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    
    my $type_id = $schema->resultset("Cv::Cvterm")->search({ name=>"plot" })->first->cvterm_id();
    
    print STDERR "PLOT TYPE ID $type_id\n";

    my @missing = ();
    foreach my $l (@$list) { 
	my $rs = $schema->resultset("Stock::Stock")->search(
	    { 
		type_id=>$type_id,
		name => $l, 
	    });	
	if ($rs->count() == 0) { 
	    push @missing, $l;
	}
    }
    return { missing => \@missing };
}

1;
