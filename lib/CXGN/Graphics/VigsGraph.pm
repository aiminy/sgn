
package CXGN::Graphics::VigsGraph;

use Moose;
use GD::Image;
use Data::Dumper;
use Bio::SeqIO;


use Bio::BLAST::Database;


has 'bwafile' => ( is=>'rw' );
has 'fragment_size' => (is => 'rw', isa=>'Int', default=>21);
has 'matches' => (is=>'rw', isa=>'Ref');
has 'seq_window_size' => (is=>'rw', isa=>'Int', default=>100);
has 'seq_fragment' => (is=>'rw', isa=>'Int', default=>300);
has 'query_seq' => (is=>'rw', isa=>'Str');
has 'step_size' => (is=>'rw', isa=>'Int', default=>4);
has 'width' => (is=>'rw', isa=>'Int', default=>700);
has 'height'=> (is=>'rw', isa=>'Int', default=>3600);
has 'font' => (is =>'rw', isa=>'GD::Font');
has 'ruler_height' => (is => 'ro', isa=>'Int', default=>20);
has 'expr_hash' => (is => 'rw', default=>undef);
has 'link_url' => (is => 'rw', isa=>'Str');

sub parse { 
    my $self = shift;
    my $mm = shift || 0;
    # warn("Parsing file ".$self->bwafile()."\n");

    open(my $bt2_fh, "<", $self->bwafile()) || die "Can't open file ".$self->bwafile();

    my $matches = {};
    
    # parse Bowtie2 file
    while (my $line = <$bt2_fh>) { 
	my ($seq_id, $code, $subject, $scoord) = (split /\t/, $line);
	
	# get perfect matches 
	if ($line =~ /XM:i:(\d+)/) { 
	    my $mm_found = $1;

	    if ($mm_found <= $mm) {
		my ($start_coord, $end_coord);
		if ($seq_id=~/(\d+)/)  {
		    $start_coord = $1;
		    $end_coord = $start_coord+$self->fragment_size() -1;
		}
	    
		# new match sequence object
		my $ms = CXGN::Graphics::VigsGraph::MatchSegment->new();
		$ms->start($start_coord);
		$ms->end($end_coord);
		$ms->id($subject);

		push @{$matches->{$subject}}, $ms;
	    }
	}
    }
    $self->matches($matches);
}
 
sub matches_in_interval { 
    my $self = shift;
    my $start = shift;
    my $end = shift;
    
    my $matches = $self->matches();
    my $interval = {};

    foreach my $s (keys(%$matches)) { 
	# print  $s."\n";
	foreach my $m (@{$matches->{$s}}) { 
	    # print STDERR "checking coords $m->[0], $m->[1] (start, end = $start, $end)\n";
	    if ( ($m->start() > $start) && ( $m->start() < $end) || ($m->end() > $start ) && ($m->end() < $end)) { 
		# print STDERR "Match found for sequence $s: $m->[0], $m->[1] ($start, $end)\n";
		push @{$interval->{$s}}, $m;
	    }
	}
    }
    return $interval;
}

sub target_graph { 
    my $self = shift;
    my $coverage = shift;

    my $matches = $self->matches();
    my @match_counts = $self->subjects_by_match_count(0,$matches);
    # print Dumper(@match_counts);
    my @target_scores;

    # array with target subject names, coverage is the number of target subjects
    my @target_keys = ();
    foreach my $k (1..$coverage) { 
	my $e = shift @match_counts;
	push @target_keys, $e->[0]; 
    }

#    print STDERR "TARGET KEYS: ".join(",", @target_keys);
#    print STDERR "\n";
   
    # foreach match (blue squares in the graph), saves in $s_targets the coverage in each position
    foreach my $s (@target_keys) { 
	if (! defined($matches->{$s})) { 
	    next; 
	}
	my %s_targets = ();
	foreach my $m (@{$matches->{$s}}) { 
	    # print STDERR "m: ".$m->start()."\n";
	    foreach my $n ($m->start()-1 .. $m->end()) { 
		$s_targets{$n} = 1;
                # print STDERR "m: ".$m->start()." - ". $m->end()." $n\n";
	    }   
	}

	# when the position is not mapped over the targets we get 0, 
        # if it is mapped we get the number of targets where mapped in that position
	foreach my $pos (sort keys %s_targets) {
	    $target_scores[$pos]++;
	}
	%s_targets = ();	
    }

    return @target_scores;
}

sub off_target_graph { 
    my $self = shift;
    my $coverage = shift;

    my @off_targets = ();

    my $matches = $self->matches();
    my @match_counts = $self->subjects_by_match_count(0,$matches);
    my %off_t_counts;

    my @coverage_keys = ();
    foreach my $k (0..$coverage-1) { 
	shift @match_counts;
    }
    @coverage_keys = map { $_->[0] } @match_counts;
    
    foreach my $s (@coverage_keys) { 
	foreach my $m (@{$matches->{$s}}) {
#	    print STDERR "$s, ".$m->start()."-".$m->end()."\n";
	    foreach my $n ($m->start()-1 .. $m->end()) {
		$off_t_counts{$n} = 1;
	    }
	}
	
	foreach my $pos (sort keys %off_t_counts) {
	    $off_targets[$pos]++;
	}
	%off_t_counts = ();
    }

    return @off_targets;
}

sub longest_vigs_sequence { 
    my $self = shift;
    my $coverage = shift;
    my $seq_length = shift;

    my @best_region;    
    my $start = undef;
    my $end = undef;
    my $score = 0;
    my @window_sum = [];
    my $window_score = 0;
    my $best_score = -9999;
    my $best_start = 1;
    my $best_end = 1;
    my $no_result = 0;
    
    if ($coverage == 0) {
	$coverage = 1;
	$no_result = 1;
    }
    
    my @targets = $self->target_graph($coverage);
    my @off_targets = $self->off_target_graph($coverage);
    my $seq_fragment = $self->seq_fragment();

    # @targets contains the coverage of target at every position. Same thing for off_targets
    # $window sum[position] contain the score for each position. 
    # It will be positive when there are more targets than off_targets, and negative in the opposite case.
    for (my $i=0; $i<$seq_length; $i++) {
        
	$window_sum[$i] = 0;
	if (defined($targets[$i]) && $targets[$i]>0) {
	    $window_sum[$i] += $targets[$i];
	}
	else {
	    $window_sum[$i] += 0;
	    $targets[$i] = 0;
	}

	if (defined($off_targets[$i]) && $off_targets[$i]>0) {
	    $window_sum[$i] -= ($off_targets[$i]*1.5);
	}
	else {
	    $window_sum[$i] += 0;
	    $off_targets[$i] = 0;
	}

#	print "$i: $window_sum[$i]\tt:$targets[$i]\tot:$off_targets[$i]\n";

	if ($i+1 >= $seq_fragment) {
	    $window_score = 0;
	    for (my $e=($i-$seq_fragment+1); $e<=$i; $e++) {
#		print "$e\t";
		if ($window_sum[$e] && $window_sum[$e] =~ /^[\d+-\.]+$/) { 
		    $window_score += $window_sum[$e];
		}
	    }
#	    print "\ntest: ".($i+1-$seq_fragment)."-".($i).": $window_score\n";

	    if ($window_score > $best_score) {
		$best_score = $window_score;
		$best_start = $i-$seq_fragment+1;
		$best_end = $i;
	    }
#	    print "best: $best_start-$best_end: $best_score\n";
	    $window_score = 0;
	}
    }
    if ($no_result) {$best_score = 0;}
    
    @best_region = ($coverage, $best_score, \@window_sum, $seq_fragment, $best_start, $best_end);
    return @best_region;
}



sub sort_keys { 
    $b->[1] <=> $a->[1];
}

sub get_best_coverage { 
    my $self = shift;
    my @subjects = $self->subjects_by_match_count(0,$self->matches);
    
#    print Dumper(\@subjects);
    
    # detect a high gap in the number of reads mapped between subjects
    for (my $i=1; $i<@subjects; $i++) {
	if ($subjects[$i-1]->[1] * 0.5 > $subjects[$i]->[1]) { 
	     # print STDERR "COVERAGE: $i\n";
	    return $i;
	}
    }
    return 0;
}

sub subjects_by_match_count { 
    my $self = shift;
    my $db = shift;
    my $matches = shift;
    my @counts = ();
    my $fs;
    my $primseqi;
    my $desc;

    if ($db) {
	#print STDERR "db: $db\n";
    
	$fs = Bio::BLAST::Database->open(
	    full_file_basename => $db,
	);
    }

    foreach my $s (keys %$matches) { 
        if ($db) {
	    $primseqi = $fs->get_sequence($s);
	    $desc = $primseqi->desc();

	    push @counts, [ $s, scalar(@{$matches->{$s}}),$desc];
	} else {
	    push @counts, [ $s, scalar(@{$matches->{$s}}),"" ];
	}
    }

    # print Dumper(\@counts);
    my @sorted = sort sort_keys @counts;
    
    return @sorted;
}

sub uniq_array{
    my %hash;
    my $input = shift;
    for my $e (@{$input}) {
	$hash{$e}=1;
    }
    
    my (@output) = sort {$a <=> $b} keys %hash;
    return \@output;
}

sub get_matches { 
    my $self = shift;
    my @all_matches;

    #HoAoH
    my $matches_h = $self->matches();
    
    foreach my $key (sort{$#{$$matches_h{$b}}<=>$#{$$matches_h{$a}}} keys(%{$matches_h})) {
	my @subject_a;
	for (my $i=0; $i<@{$$matches_h{$key}}; $i++) {
#	    print STDERR "start: $$h{'start'}, end: $$h{'end'}\n";
	    # to remove duplicates
	    if ($i > 0 && $$matches_h{$key}[$i]{'start'} != $$matches_h{$key}[$i-1]{'start'}) {
		push(@subject_a, "$$matches_h{$key}[$i]{'start'}-$$matches_h{$key}[$i]{'end'}");
	    } elsif ($i == 0) {
		push(@subject_a, "$$matches_h{$key}[$i]{'start'}-$$matches_h{$key}[$i]{'end'}");		
	    }
	}
	push(@all_matches, \@subject_a);
    }
#    print Dumper(@all_matches);

    return \@all_matches;
}

sub add_expression_values {
    my $self = shift;
    my $expr_hash = shift;
    my @expr_msg;
    my @sorted = $self->subjects_by_match_count(0,$self->matches);

# $sorted[$track]->[0]
    for (my $track=0; $track< @sorted; $track++) {

	my $subject_msg = "$sorted[$track]->[0]";
	if (defined($$expr_hash{"header"})) {
	    for (my $i=0; $i<length($$expr_hash{"header"}); $i++) {
		if (defined($$expr_hash{$sorted[$track][0]}[$i])) {
		    $$expr_hash{"header"}[$i+1] =~ s/\s+/_/g;
		    my $col_value = $$expr_hash{$sorted[$track][0]}[$i];
		    if (($col_value =~ /^\d+\.(\d+)$/) && (length($1) > 5)) {
			$col_value = sprintf("%.6f",$col_value);
		    }
		    $subject_msg = "$subject_msg    $$expr_hash{'header'}[$i+1]: $col_value";
		}
	    }
	}
	push(@expr_msg,[$subject_msg,""]);
    }
    #print STDERR "msg: $expr_msg[0]\n";
    return @expr_msg;
}

sub get_img_height { 
    my $self = shift;
    my $img_height = 20; #grid on top
    my $max_row_num = 0;
    my $row_num = 1;
    my $prev_end = 0;

    #HoAoH
    my $matches_h = $self->matches();
    
    foreach my $key (keys(%{$matches_h})) {
	foreach my $h (@{$$matches_h{$key}}) {
	    if ($$h{'start'} <= $prev_end) {
		$row_num++;
	    } else {
		$row_num = 1;
	    }
	    if ($max_row_num < $row_num && $row_num <= $self->fragment_size) {$max_row_num = $row_num;}
	    if ($max_row_num == $self->fragment_size) {last;}

#	    print STDERR "start: $$h{'start'}, end: $$h{'end'}\n";
	    $prev_end = $$h{'end'};
	}
	$img_height += (($max_row_num*4) + 30); # rectangles height + before and after the block values
#        print STDERR "max_row_num: $max_row_num\n";

	$max_row_num = 0;
	$prev_end = 0;
	$row_num = 0;
    }
#    print STDERR "IMAGE HEIGHT: $img_height\n";
    
    return $img_height;
}


package CXGN::Graphics::VigsGraph::MatchSegment;

use Moose;

has 'start' => (is => 'rw', isa=>'Int');
has 'end'   => (is => 'rw', isa=>'Int');
has 'id'    => (is => 'rw');
has 'score' => (is => 'rw', isa=>'Int');
has 'matches' => (is => 'rw', isa=>'Int');
has 'offsite_matches' => (is => 'rw', isa=>'Int');


	
1;
