class CompilationTest2 implements dci.Context 
{
    public static function main() {}

    public function new(source) {
        this.source = source;
    }

    public function start() {
    	// Should fail here, because source.decreaseBalance isn't public.
        this.source.decreaseBalance();
    }

    @role var source : {
		function decreaseBalance() : Void;

        public function withdraw() {}
    }
}
