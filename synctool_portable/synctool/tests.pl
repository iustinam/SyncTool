#src/dest file/folder 


# sets all types of attrs on some random selected files from source
sub set_attributes{
    print "######### some testing on deleting files with diff attrs set\n";
    my $attr;
    Win32::File::SetAttributes($d_path,0|COMPRESSED);
    Win32::File::GetAttributes($d_path,$attr);
    if ( $attr&COMPRESSED){ print "test: COMPRESSED was  set\n";}
    unlink($d_path)&&print("deleted COMPRESSED\n") or print "test: $!\n";
    if(copy_one($s_path,$d_path)) {print "copy fail\n";}
    
    Win32::File::SetAttributes($d_path,0|OFFLINE);
    Win32::File::GetAttributes($d_path,$attr);
    if ( $attr&OFFLINE){ print "test: OFFLINE was  set\n";}
    unlink($d_path)&&print("deleted OFFLINE\n") or print "test: $!\n"; 
    if(copy_one($s_path,$d_path)) {print "copy fail\n";}                   
    
    Win32::File::SetAttributes($d_path,0|SYSTEM);
    Win32::File::GetAttributes($d_path,$attr);
    if ( $attr&SYSTEM){ print "test: SYSTEM was  set\n";}
    unlink($d_path)&&print("deleted SYSTEM\n") or print "test: $!\n";
    if(copy_one($s_path,$d_path)) {print "copy fail\n";}
    
    Win32::File::SetAttributes($d_path,0|TEMPORARY);
    Win32::File::GetAttributes($d_path,$attr);
    if ( $attr&TEMPORARY){ print "test: TEMPORARY was  set\n";}
    unlink($d_path)&&print("deleted TEMPORARY\n") or print "test: $!\n";
    if(copy_one($s_path,$d_path)) {print "copy fail\n";}
    
    Win32::File::SetAttributes($d_path,0|ARCHIVE);
    Win32::File::GetAttributes($d_path,$attr);
    if ( $attr&ARCHIVE){ print "test: ARCHIVE was  set\n";}
    unlink($d_path)&&print("deleted ARCHIVE\n") or print "test: $!\n";
    if(copy_one($s_path,$d_path)) {print "copy fail\n";}
    
    Win32::File::SetAttributes($d_path,0|HIDDEN);
    Win32::File::GetAttributes($d_path,$attr);
    if ( $attr&HIDDEN){ print "test: HIDDEN was  set\n";}
    unlink($d_path)&&print("deleted HIDDEN\n") or print "test: $!\n";
    if(copy_one($s_path,$d_path)) {print "copy fail\n";}
    
    Win32::File::SetAttributes($d_path,0|READONLY);
    Win32::File::GetAttributes($d_path,$attr);
    if ( $attr&READONLY){ print "test: READONLY was  set\n";}
    unlink($d_path)&&print("deleted READONLY\n") or print "test: $!\n";
    if(copy_one($s_path,$d_path)) {print "copy fail\n";}
    
    Win32::File::SetAttributes($d_path,0|NORMAL);
    Win32::File::GetAttributes($d_path,$attr);
    if ( $attr&NORMAL){ print "test: NORMAL was  set\n";}
    unlink($d_path)&&print("deleted NORMAL\n") or print "test: $!\n";
    if(copy_one($s_path,$d_path)) {print "copy fail\n";}
    
    Win32::File::SetAttributes($d_path,0|DIRECTORY);
    Win32::File::GetAttributes($d_path,$attr);
    if ( $attr&DIRECTORY){ print "test: DIRECTORY was  set\n";}
    unlink($d_path)&&print("deleted DIRECTORY\n") or print "test: $!\n";
    if(copy_one($s_path,$d_path)) {print "copy fail\n";}
    
    print "######## ended testing\n";
}