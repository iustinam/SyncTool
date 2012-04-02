use Win32::File;
use File::Spec; 
my $s_path='\\\\rbgs392x\\did01524\\SW\\TestSyncTool\\mmpenv.MMP_Environment_for_DS_Client\\MsVisualStudio2005+Sp1\\MergeMod\\mergemod.dll';
#my $s_path=File::Spec->catfile('\\rbgs392x\did01524\SW\TestSyncTool\mmpenv.MMP_Environment_for_DS_Client\MsVisualStudio2005+Sp1\MergeMod\mergemod.dll');
my $d_path='\\\\iad3488d\\tcp_software\\TestSyncTool\\mmpenv.MMP_Environment_for_DS_Client\\MsVisualStudio2005+Sp1\\MergeMod\\mergemod.dll';
my $s_attr; my $d_attr;
Win32::File::GetAttributes( $s_path, $s_attr );
Win32::File::GetAttributes( $d_path, $d_attr );
if ( ($s_attr|ARCHIVE) != ($d_attr|ARCHIVE) ) {

	print  "attrs differ.." ;		
}else {
	print "ok\n\n";
}
use constant{
FILE_ATTRIBUTE_DEVICE=>64,
FILE_ATTRIBUTE_ENCRYPTED=>16384,
FILE_ATTRIBUTE_INTEGRITY_STREAM=>32768 ,
FILE_ATTRIBUTE_NOT_CONTENT_INDEXED=>8192, 
FILE_ATTRIBUTE_NO_SCRUB_DATA=>131072,
FILE_ATTRIBUTE_REPARSE_POINT=>1024, 
FILE_ATTRIBUTE_SPARSE_FILE=>512, 
FILE_ATTRIBUTE_VIRTUAL=>65536,
};

my $attr_types={
    'COMPRESSED'=>COMPRESSED,
    'OFFLINE'=>OFFLINE,
    'SYSTEM'=>SYSTEM,
    'TEMPORARY'=>TEMPORARY,
    'ARCHIVE'=>ARCHIVE,
    'HIDDEN'=>HIDDEN,
    'READONLY'=>READONLY,
    'NORMAL'=>NORMAL, #DIRECTORY
'DEVICE'=>64,
'ENCRYPTED'=>16384,
'INTEGRITY_STREAM'=>32768 ,
'NOT_CONTENT_INDEXED'=>8192, 
'NO_SCRUB_DATA'=>131072,
'REPARSE_POINT'=>1024, 
'SPARSE_FILE'=>512, 
'VIRTUAL'=>65536,
};
sub printAllAttrs{
    my ($d_path)=@_;
    my $attrs;
    print "$d_path has: ";
    #print Dumper(keys %$attr_types);
    foreach(keys %$attr_types){
        Win32::File::GetAttributes($d_path,$attrs);
        my $a=$attr_types->{$_};
        if ( $attrs & $a ){ 
            print $_." ";
        }
    }
    print "\n";
}
if(-f $s_path){print "file\n";}else{print "nok\n";}
if(-f $d_path){print "file\n";}else{print "nok\n";}

printAllAttrs($s_path);
printAllAttrs($d_path);