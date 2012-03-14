
if(not system('SC QUERY state= all |findstr "SyncTool"')){
    print "installed\n";
    if(system('sc query SyncToolService | FIND "STATE" | FIND "RUNNING"')){
        print "not running\n";   
    }else{
        print "running\n";
    }   
}



