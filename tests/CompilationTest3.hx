class CompilationTest3 implements dci.Context 
{
    public static function main() {}

    public function new(source, destination) {
        this.source = source;
        bind(destination);
    }

    public function bind(dest) {
        // Should fail here, since all roles should be bound in the same function
        this.destination = dest;
    }

    public function start() {
    }
	
    @role var source : {
		function decreaseBalance() : Void;

        public function withdraw() {}		
    }

    @role var destination : {
        function decreaseBalance() : Void;
    }
}
