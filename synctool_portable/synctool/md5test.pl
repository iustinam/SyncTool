use Digest::MD5;

sub md5 {
    my ($f) = shift;
    open( FH, '<', $f ) or return ("");
    binmode(FH);
    my $ret = Digest::MD5->new->addfile(*FH)->hexdigest();
    close FH;
    return $ret;
}
my $s=time;
print "err" if not -f $ARGV[0];
print "ok" if -f $ARGV[0];
print md5($ARGV[0]);
print "\n".eval(time-$s)."\n";