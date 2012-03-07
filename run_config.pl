#RUN CONFIG ITEMSETS

# This file contains the informations for the binary to run with run.pl
#!/usr/bin/perl

$TIMEOUT=150; #In number of cycles
$CYCLE_LEN=10; #in sec.
$MAX_MEM_USAGE=60000000;
$DATASET_EXT = '.dat';

$DATA_DIR = 'data/';

$clogen = '../../algorithms/clogen/clogen_itemsets';
$lcm = 'lcm25/fim_closed';
$plcm_old = 'plcm_ng_quicksort/plcm';
$dci = 'dci-closed/multi-closed';
$plcm = '../../algorithms/plcm/plcm';
$noop = '/bin/echo ';

$bin{lcm} = {bin=>$lcm,
	     command=>"$lcm DATASET SUP /dev/null",
	     time_func=>\&extract_time_null,
	     par=>0,
}; 

$bin{plcm_old} = {bin=>$plcm_old,
	     command=>$plcm_old."NBTHREADS DATASET SUP /dev/null",
	     time_func=>\&extract_time_plcm,
	     par=>1,
}; 


$bin{dci} = {bin=>$dci,
	     command=>"$dci DATASET SUP /dev/null NBTHREADS 60000",
	     time_func=>\&extract_time_dci,
	     par=>1,
}; 


$bin{plcm} = {bin=>$plcm,
	      command=>$plcm."NBTHREADS DATASET SUP /dev/null",
	      time_func=>\&extract_time_plcm,
	      par=>1,
	      run=>0, 
}; 


$bin{clogen} = {bin=>$clogen,
	      command=>$clogen." -t NBTHREADS DATASET SUP > /dev/null",
	      time_func=>\&extract_time_plcm,
	      par=>1,
	      run=>0, 
}; 



sub extract_time {
    # Retrieve computation time value

    open(F_IN, $_[0]) or die "cannot open $_[0] output file.\n"; 
    my @lines = <F_IN> ;
    close(F_IN);
    chomp $lines[0];
    if($lines[0] eq "SUCCESS"){
	open (F_IN, "time_tmp") ;
	
	@lines = <F_IN> ;
	close F_IN ;
	
	chomp $lines[0];
	return  $lines[0] ;
    }
    else{
	dumpOutputs;
	die "TIMEOUT";
	chomp $lines[0];
	print $lines[0];
	return  $lines[0];
    }

}

sub extract_time_null{
    return '0';
}

sub extract_time_dci{
    my $nb_threads=$_[1];
    open(INPUT, $_[0]) or die "cannot open $_[0] output file.\n";
    my $count = 0; 
    my $time_sum; 
    while(my $line = <INPUT>){
	if($line =~ /Time: ([0-9.]+).*/){
	    $count++;
	    if($count <= 3){
		$time_sum+=$1; 
	    }
	    elsif ($count == 4){
		;
		#$time_sum+=$1/$nb_threads;
	    }
	}
    }

    if($count < 5){
	print STDERR "Could not parse output $count\n"; 
	return "XXX"; 
    }
    return $time_sum;
}


sub extract_time_plcm{
    open(INPUT, $_[0]) or die "cannot open $_[0] output file.\n";
    my $count = 0; 
    my $time_sum; 
    while(my $line = <INPUT>){
	if($line =~ /TIME ([0-9.]+).*/){
	    return $1;
	}
    }
    print STDERR "Could not parse output\n"; 
    return "XXX";

}
