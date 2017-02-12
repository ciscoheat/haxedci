class CompilationTest1 implements dci.Context 
{
	public static function main() {}

    public function new(source) {
        this.source = source;
    }

    public function start() {
    	// Should fail here, because source.withdraw isn't public.
        this.source.withdraw();
    }
	
    @role var source : {
		function decreaseBalance() : Void;

        function withdraw() {}
    }
}
