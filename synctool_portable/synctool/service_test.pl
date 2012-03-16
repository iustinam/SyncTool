
#open H, 'SC QUERY state= all |findstr "SyncTool" |' or die("er1");
#my $res=<H>;
#if( $res){
if(not system('SC QUERY state= all |findstr "SyncTool" ')){
    print "installed\n";
    if(system('sc query SyncToolService | FIND "STATE" | FIND "RUNNING"')){
        print "not running\n";   
    }else{
        print "running\n";
    }   
}



