# Copyright (C) 2010-2013, Benjamin Negrevergne.
package System_API; #Using expression parser
use 5.012; 
use strict;
use Exporter 'import';
our @EXPORT = qw(md5_file date_string data_string_ymd get_total_memory get_process_table 
memory_usage_process_tree check_memory_usage get_memory_usage reset_memory_usage check_timeout get_hostname extract_process_name extract_bin_filename kill_process_tree create_temp_file); 

use strict;
use warnings;

use File::Temp qw/ tempfile/;
use Proc::ProcessTable;

sub md5_file{
    die if @_ != 1; 
    my $file = $_[0];
    use Digest::MD5;
    
    my $md5; 
    if(open(FILE, $file)){
    binmode(FILE);
    $md5 = Digest::MD5->new->addfile(*FILE)->hexdigest;
    }
    else{
	Runtime::warning_output( "Cannot compute binary md5 file for '$file': ".$!);
	$md5 = "(Cannot compute md5 for file: '$file')"; 
    }
    return $md5; 
}

sub date_string{
    use POSIX qw/strftime/;
    return strftime('%F %T',localtime); 
}

sub date_string_ymd{
    use POSIX qw/strftime/;
    return strftime('%F',localtime); 
}


# Warning: may die; 
sub get_total_memory{
    die if @_ != 0; 
    
    open MEMINFO, "/proc/meminfo" or die $!; 
    while (my $line = <MEMINFO>){
	if($line =~ /MemTotal.*?([0-9]+).*/){
	    close MEMINFO; 
	    return $1; 
	}
    }
    die "Error: Cannot find out total memory.\n";
}

sub get_process_table{
    die if @_ != 0; 
     return new Proc::ProcessTable;
}


# compute memory of the memory usage .. in kib
sub memory_usage_process_tree{
    die if @_ != 1; 
    my ($pid) = @_;
    my $t = get_process_table;
    
    my $mem = 0; 
    foreach my $p (@{$t->table}) {
	if($p->{"pid"} == $pid){ # found current process
	    $mem += $p->{"rss"} / 1024; # in kib
	}
	
	if($p->{"ppid"} == $pid){ # found child process 
	    $mem += memory_usage_process_tree($p->{"pid"}); 
	}
    }
    
    return $mem; 

}

my $max_mem_usage = 0; # maximum memory usage of the current process
sub check_memory_usage{
    die if @_ != 2;
    my ($pid, $mem_usage_cap) = @_; 
    my $mem_usage = memory_usage_process_tree($pid);

    if($mem_usage > $max_mem_usage){
	$max_mem_usage = $mem_usage; 
    }
    if($mem_usage_cap == -1) { 
	return 0; 
    }
    else{
	return ($mem_usage >= $mem_usage_cap); 
    }
}

sub get_memory_usage{
    die if @_ != 0; 
    return $max_mem_usage; 
}

sub reset_memory_usage{
    die if @_ != 0; 
    $max_mem_usage = 0; 
}

sub check_timeout{
    die if @_ != 2; 
    my ($current_time, $timeout) = @_; 
    if($timeout == -1){
	return 0; 
    }
    else{
	return ($current_time >= $timeout); 
    }
}




sub get_hostname{
    die if @_ != 0; 
    use Sys::Hostname;
    my $hostname = hostname; 
    return $hostname; 
}

# Extract process name from a command line. 
sub extract_process_name{
    die if @_ != 1; 
    my ($command) = @_;
    my $process_name = "unknwown_process"; 

    if( $command =~ /.*?\/?([\w\-]+)\s/gx){
	$process_name = $1;
    }
    else {
	print STDERR "Error: cannot parse process name \n"; 
    }
    return $process_name; 
}

# Extract bin file name from a command line. 
sub extract_bin_filename{
    die if @_ != 1; 
    my ($command) = @_;
    my $process_name = "unknwown_process"; 

    if( $command =~ /(.*?\/?[\w\-]+)\s/gx){
	$process_name = $1;
    }
    else {
	print STDERR "Error: cannot parse process name \n"; 
    }
    return $process_name; 
}

sub kill_process_tree{
    die if @_ != 1; 
    my ($pid) = @_;
    my $t = get_process_table;
    
    foreach my $p (@{$t->table}) {
	if($p->{"ppid"} == $pid){
	    kill_process_tree($p->{"pid"}); 
	}
    }
    kill 9, $pid; 
}

sub create_temp_file{
    die if @_ != 1; 
    my ($filename) = @_; 

    return tempfile('/tmp/runtime_'.$filename.'_XXXX');
}

1; 
