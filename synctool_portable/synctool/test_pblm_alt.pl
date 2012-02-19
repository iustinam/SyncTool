use Win32::File;

my $s_path='\\iasp351x\didl9505\SCC\DOORS\9.2\BU_MM_DOORS_HKEY_LOCAL_MACHINE_SOFTWARE_Telelogic.reg';
my $d_path='\\ias1781c\SCC\DOORS\9.2\BU_MM_DOORS_HKEY_LOCAL_MACHINE_SOFTWARE_Telelogic.reg';

Win32::File::GetAttributes( $s_path, $s_attr ); print $s_attr."\n";
Win32::File::GetAttributes( $d_path, $d_attr ); print $d_attr."\n";

if ( $s_attr|ARCHIVE != $d_attr|ARCHIVE ) {
                #if ( $opt{v} ) {
                    print "attrs for dirs differ..";
                #}
}else{
    print "ok";   
}



