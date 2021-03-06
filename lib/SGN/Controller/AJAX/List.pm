
package SGN::Controller::AJAX::List;

use Moose;
use CXGN::List::Validate;


BEGIN { extends 'Catalyst::Controller::REST'; }

__PACKAGE__->config(
    default   => 'application/json',
    stash_key => 'rest',
    map       => { 'application/json' => 'JSON', 'text/html' => 'JSON' },
   );

sub get_list :Path('/list/get') Args(0) { 
    my $self = shift;
    my $c = shift;

    my $list_id = $c->req->param("list_id");

    my $user_id = $self->get_user($c);
    if (!$user_id) { 
	$c->stash->{rest} = { error => 'You must be logged in to use lists.', }; 
	return;
    }

    my $list = $self->retrieve_list($c, $list_id);

    $c->stash->{rest} = $list;
   
			  
}


sub get_list_data :Path('/list/data') Args(0) { 
    my $self = shift;
    my $c = shift;

    my $list_id = $c->req->param("list_id");

    my $user_id = $self->get_user($c);
    if (!$user_id) { 
	$c->stash->{rest} = { error => 'You must be logged in to use lists.', }; 
	return;
    }

    my $list = $self->retrieve_list($c, $list_id);

    my ($type_id, $list_type) = $self->retrieve_type($c, $list_id);

    $c->stash->{rest} = { 
	type_id     => $type_id,
	type_name   => $list_type,
	elements    => $list,
    };
			  
}



sub retrieve_list { 
    my $self = shift;
    my $c = shift;
    my $list_id = shift;

    my $q = "SELECT list_item_id, content from sgn_people.list join sgn_people.list_item using(list_id) WHERE list_id=?";

    my $h = $c->dbc->dbh()->prepare($q);
    $h->execute($list_id);
    my @list = ();
    while (my ($id, $content) = $h->fetchrow_array()) { 
	push @list, [ $id, $content ];
    }
    my $q = "SELECT list_item_id, content from sgn_people.list join sgn_people.list_item using(list_id) WHERE list_id=?";

    my $h = $c->dbc->dbh()->prepare($q);
    $h->execute($list_id);
    my @list = ();
    while (my ($id, $content) = $h->fetchrow_array()) { 
	push @list, [ $id, $content ];
    }
    return \@list;
}


sub retrieve_type { 
    my $self = shift;
    my $c = shift;
    my $list_id = shift;
    my $q = "SELECT type_id, cvterm.name FROM sgn_people.list JOIN cvterm ON (type_id=cvterm_id) WHERE list_id=?";
    my $h = $c->dbc->dbh()->prepare($q);
    $h->execute($list_id);
    my ($type_id, $list_type) = $h->fetchrow_array();
    return ($type_id, $list_type);
}

sub get_type :Path('/list/type') Args(1) { 
    my $self = shift;
    my $c = shift;
    my $list_id = shift;

    my ($type_id, $list_type) = $self->retrieve_type($c, $list_id);
    
    $c->stash->{rest} = { type_id => $type_id,
			  list_type => $list_type,
    };
}

sub set_type :Path('/list/type') Args(2) { 
    my $self = shift;
    my $c = shift;
    my $list_id = shift;
    my $type = shift;

    my $user_id = $self->get_user($c);

    if (!$user_id) { 
	$c->stash->{rest} = { error => "You need to be logged in to set the type of a list" };
	return;
    }

    my $schema = $c->dbic_schema("Bio::Chado::Schema");
    my $rs = $schema->resultset("Cv::Cvterm")->search({ 'me.name' => $type }, { join => "cv" });
    if ($rs->count ==0) { 
	$c->stash->{rest}= { error => "The type specified does not exist" };
	return;
    }
    my $type_id = $rs->first->cvterm_id();

    my $q = "SELECT owner FROM sgn_people.list WHERE list_id=?";
    my $h = $c->dbc->dbh->prepare($q);
    $h->execute($list_id);

    my ($list_owner) = $h->fetchrow_array();

    if ($list_owner != $user_id) { 
	$c->stash->{rest} = { error => "Only the list owner can change the type of a list" };
	return;
    }

    eval { 
	$q = "UPDATE sgn_people.list SET type_id=? WHERE list_id=?";
	$h = $c->dbc->dbh->prepare($q);
	$h->execute($type_id, $list_id);
    };
    if ($@) { 
	$c->stash->{rest} = { error => "An error occurred. $@" };
	return;
    }
    
    $c->stash->{rest} = { success => 1 };
    
}

sub new_list :Path('/list/new') Args(0) { 
    my $self = shift;
    my $c = shift;

    my $name = $c->req->param("name");
    my $desc = $c->req->param("desc");


    my $user_id = $self->get_user($c);
    if (!$user_id) { 
	$c->stash->{rest} = { error => "You must be logged in to use lists", }; 
	return;
    }
	
    my $new_list_id = 0;
    eval { 
	my $q = "INSERT INTO sgn_people.list (name, description, owner) VALUES (?, ?, ?)";
	my $h = $c->dbc->dbh->prepare($q);
	$h->execute($name, $desc, $user_id);
	
	$q = "SELECT currval('sgn_people.list_list_id_seq')";
	$h = $c->dbc->dbh->prepare($q);
	$h->execute();
	($new_list_id) = $h->fetchrow_array();
	
    };

    if ($@) { 
	$c->stash->{rest} = { error => "An error occurred, $@", };
	return;
    }
    else { 
	$c->stash->{rest}  = { list_id => $new_list_id };
    }
}

sub all_types : Path('/list/alltypes') :Args(0) { 
    my $self = shift;
    my $c = shift;
    
    my $q = "SELECT cvterm_id, cvterm.name FROM cvterm JOIN cv USING(cv_id) WHERE cv.name = 'list_types' ";
    my $h = $c->dbc->dbh->prepare($q);
    $h->execute();
    my @all_types = ();
    while (my ($id, $name) = $h->fetchrow_array()) { 
	push @all_types, [ $id, $name ];
    }
    $c->stash->{rest} = \@all_types;

}

sub available_lists : Path('/list/available') Args(0) { 
    my $self = shift;
    my $c = shift;

    my $user_id = $self->get_user($c);
    if (!$user_id) { 
	#$c->stash->{rest} = { error => "You must be logged in to use lists.", };
	return;
    }

    my $q = "SELECT list_id, list.name, description, count(distinct(list_item_id)), type_id, cvterm.name FROM sgn_people.list left join sgn_people.list_item using(list_id) LEFT JOIN cvterm ON (type_id=cvterm_id) WHERE owner=? GROUP BY list_id, list.name, description, type_id, cvterm.name ORDER BY list.name";
    my $h = $c->dbc->dbh()->prepare($q);
    $h->execute($user_id);

    my @lists = ();
    while (my ($id, $name, $desc, $item_count, $type_id, $type) = $h->fetchrow_array()) { 
	push @lists, [ $id, $name, $desc, $item_count, $type_id, $type ] ;
    }
    $c->stash->{rest} = \@lists;
}

sub add_item :Path('/list/item/add') Args(0) { 
    my $self = shift;
    my $c = shift;

    my $list_id = $c->req->param("list_id");
    my $element = $c->req->param("element");

    my $user_id = $self->get_user($c);
    if (!$user_id) { 
	$c->stash->{rest} = { error => "You must be logged in to add elements to a list" };
	return;
    }

    if (!$element) { 
	$c->stash->{rest} = { error => "You must provide an element to add to the list" };
	return;
    }
    
    if (!$list_id) { 
	$c->stash->{rest} = { error => "Please specify a list_id." };
	return;
    }

    eval { 
	my $iq = "INSERT INTO sgn_people.list_item (list_id, content) VALUES (?, ?)";
	my $ih = $c->dbc->dbh()->prepare($iq);
	$ih->execute($list_id, $element);
    };
    if ($@) { 
	$c->stash->{rest} = { error => "An error occurred: $@" };
	return;
    }
    else { 
	$c->stash->{rest} = [ "SUCCESS" ];
    }
}

sub delete_list :Path('/list/delete') Args(0) { 
    my $self = shift;
    my $c = shift;

    my $list_id = $c->req->param("list_id");
    
    my $user_id = $self->get_user($c);
    if (!$user_id) { 
	$c->stash->{rest} = { error => "You must be logged in to delete a list" };
	return;
    }
    
    my $q = "DELETE FROM sgn_people.list WHERE list_id=?";
    
    eval { 
	my $h = $c->dbc->dbh()->prepare($q);
	$h->execute($list_id);
    };
    if ($@) { 
	$c->stash->{rest} = { error => "An error occurred while deleting list with id $list_id: $@" };
	return;
    }
    else { 
	$c->stash->{rest} =  [ 1 ];
    }
}


sub exists_list : Path('/list/exists') Args(0) { 
    my $self =shift;
    my $c = shift;
    my $name = $c->req->param("name");

    my $user_id = $self->get_user($c);
    if (!$user_id) { 
	$c->stash->{rest} = { error => 'You need to be logged in to use lists.' };
    }
    my $q = "SELECT list_id FROM sgn_people.list where name = ? and owner=?";
    my $h = $c->dbc->dbh()->prepare($q);
    $h->execute($name, $user_id);
    my ($list_id) = $h->fetchrow_array();

    if ($list_id) { 
	$c->stash->{rest} = { list_id => $list_id };
    }
    else { 
	$c->stash->{rest} = { list_id => undef };
    }
}

sub exists_item : Path('/list/exists_item') :Args(0) { 
    my $self =shift;
    my $c = shift;
    my $list_id = $c->req->param("list_id");
    my $name = $c->req->param("name");

    my $user_id = $self->get_user($c);
    if (!$user_id) { 
	$c->stash->{rest} = { error => 'You need to be logged in to use lists.' };
    }
    my $q = "SELECT list_item_id FROM sgn_people.list join sgn_people.list_item using(list_id) where list.list_id =? and content = ? and owner=?";
    my $h = $c->dbc->dbh()->prepare($q);
    $h->execute($list_id, $name, $user_id);
    my ($list_item_id) = $h->fetchrow_array();

    if ($list_item_id) { 
	$c->stash->{rest} = { list_item_id => $list_item_id };
    }
    else { 
	$c->stash->{rest} = { list_item_id => 0 };
    }
}
    
sub list_size : Path('/list/size') Args(0) { 
    my $self = shift;
    my $c = shift;
    my $list_id = $c->req->param("list_id"); 
    my $h = $c->dbc->dbh->prepare("SELECT count(*) from sgn_people.list_item WHERE list_id=?");
    $h->execute($list_id);
    my ($count) = $h->fetchrow_array();
    $c->stash->{rest} = { count => $count };
}    
    
sub validate : Path('/list/validate') Args(2) { 
    my $self = shift;
    my $c = shift;
    my $list_id = shift;
    my $type = shift;

    my $list = $self->retrieve_list($c, $list_id);

    my @flat_list = map { $_->[1] } @$list;

    my $lv = CXGN::List::Validate->new();
    my $data = $lv->validate($c, $type, \@flat_list);

    $c->stash->{rest} = $data;
}


sub remove_element :Path('/list/item/remove') Args(0) { 
    my $self = shift;
    my $c = shift;
    
    my $list_id = $c->req->param("list_id");
    my $item_id = $c->req->param("item_id");
    
    
    my $h = $c->dbc->dbh()->prepare("DELETE FROM sgn_people.list_item where list_id=? and list_item_id=?");

    eval { 
	$h->execute($list_id, $item_id);
    };
    if ($@) { 
	$c->stash->{rest} = { error => "An error occurred. $@\n", };
	return;
    }
    $c->stash->{rest} = [ 1 ];
}


    
sub get_user { 
    my $self = shift;
    my $c = shift;

    my $user = $c->user;
 
    if ($user) { 
	my $user_object = $c->user->get_object();
	return $user_object->get_sp_person_id();
    }
    return undef;
}
    
