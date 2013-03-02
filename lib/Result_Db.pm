package Result_Db;

use 5.014002;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT = qw(result_db_init result_db_add_tuple result_db_set_result); 


use Using_Ast_Check;



our @result_db = ();
our %db_info = ();
our $errors = 0; 


sub error{
    die if @_ != 1; 
    print STDERR 'Error while trying to access result database: '.$_[0]."\n"; 
    $errors++;
}

sub fail_on_error{
    if($errors != 0){
	print STDERR "Cannot go further because of $errors \
    error(s) found while trying to access result database.\n";
	exit 1; 
    }
}


sub result_db_init{
    die if @_ != 1; 
    my ($output_dir) = @_;
    %db_info = (filename => $output_dir."/results.db", ready => 0, dirty => 1); 
    push @result_db, tuple_format_to_string();
    result_db_sync(); 
    fail_on_error; 
}


sub set_dirty{
    die if @_ != 0;
    $db_info{dirty} = 1; 
}

sub ensure_db_file_open{
    die if @_ != 0;
    if ($db_info{ready} == 0){
	open DB, "+>".$db_info{filename} or error "Cannot open db result file '".$db_info{filename}."' for reading and writing: $!";
	$db_info{ready} = 1;
    }
    return $db_info{ready}; 
}

sub close_db_file{
    die if @_ != 0;
    close DB; 
    $db_info{ready} = 0;
}

sub result_db_sync{
    die if @_ != 0; 
    if ($db_info{dirty} == 1){
	ensure_db_file_open();
	foreach my $line (@result_db){
	    print DB $line."\n"; 
	}
	close_db_file; 
    }
}

sub tuple_format_to_string{
    die if @_ != 0;
    my $format = ""; 
    foreach my $pname (Using_Ast_Check::all_parameter_names_in_std_order){
	$format .= "$pname\t"; 
    }
    return $format; 
}

# Add tuple in the result database, the result associated is set to UKN (unknown). 
# it can later be set using result_db_set_result
# Use serialize_tuple which require tuple to be in standard format (check serialize_tuple)
sub result_db_add_tuple{
    die if @_ != 1;
    my ($tuple) = @_; 
    push @result_db, serialize_tuple($tuple).":UKN";
    set_dirty; 
}

sub result_db_set_result{
    die if @_ != 2;
    my ($tuple, $value_string) = @_;
    my $string_tuple = serialize_tuple($tuple);

    for(my $i = 0; $i < @result_db; $i++){
    	my $line = $result_db[$i];
    	if($line =~ s/^\Q$string_tuple\E:(.*)$/$string_tuple:$value_string/){
	    $result_db[$i] = $line;
	    set_dirty; 
    	    if(not ($1 eq 'UKN')){
    		error "Value '$1' found while inserting result for $value_string";
    	    }
    	}
    }
    if ($db_info{dirty} != 1) {error "Cannot find database entry stub for tuple '$string_tuple'.";}
    result_db_sync; 
}

# Warning, must be in standard format (by default parameter values are
# lexicographically ordered by parameter names).
# Check  Using_Ast_Check::tuple_in_std_order for more details.
sub serialize_tuple{
    die if @_ != 1; 
    my ($tuple) = @_;
    return Using_Ast_Check::tuple_to_string($tuple); 
}

sub unserialize_tuple{
    die if @_ != 1; 
    my ($string_tuple) = @_;
    

}

1; 
