import buddy.*;
import dci.Self;
using buddy.Should;

class Tests extends BuddySuite implements Buddy<[Tests]> {
    public function new() {
        describe("haxedci", {
            it("should work with the specified syntax", {
				var savings = new Account("Savings", 1000);
				var home = new Account("Home", 0);

				new MoneyTransfer(savings, home, 500).transfer();

				savings.balance.should.be(500);
				home.balance.should.be(500);
			});

           it("should return properly using the 'dci.Self' type", {
				var savings = new AccountSelf("Savings", 1000);
				var home = new AccountSelf("Home", 0);

				var transfer = new MoneyTransferSelf(savings, home, 500);
				transfer.transfer();

				savings.balance.should.be(500);
				home.balance.should.be(500);

				transfer.testDestination.should.be("HomeHomePublicHomePrivate");
				transfer.testSource.should.be("HomePublic");
			});			
		});
    }
}

////////////////////////////////////////////////////////////////////

class Account {
    public var name(default, null) : String;
    public var balance(default, null) : Int;

    public function new(name, balance) {
        this.name = name;
        this.balance = balance;
    }

    public function increaseBalance(amount: Int) {
        balance += amount;
    }

    public function decreaseBalance(amount: Int) {
        balance -= amount;
    }
}

class MoneyTransfer implements dci.Context {
    public function new(source, destination, amount) {
        this.source = source;
        this.destination = destination;
        this.amount = amount;
    }

    public function transfer() {
        this.source.withdraw();
    }

    @role var source : {
		function decreaseBalance(a : Int) : Void;

        public function withdraw() {
            self.decreaseBalance(amount);
            destination.deposit();
        }
    }

    @role var destination : {
        function increaseBalance(a : Int) : Void;

        public function deposit() {
            self.increaseBalance(amount);
			return true;
        }

        function test2() return deposit();		
		function now() return Date.now();
    }

    var amount : Int;
}

///// Testing Self /////

class AccountSelf {
    public var name(default, null) : String;
	public var namePublic(default, null) : String;
	public var namePrivate(default, null) : String;
	
    public var balance(default, null) : Int;

    public function new(name, balance) {
        this.name = name;
		this.namePrivate = name + "Private";
		this.namePublic = name + "Public";
		
        this.balance = balance;
    }	
	
    public function increaseBalance(amount: Int) : AccountSelf {
        balance += amount;
		return this;
    }

    public function decreaseBalance(amount: Int) {
        balance -= amount;
		return this;
    }
}

class MoneyTransferSelf implements dci.Context {
	public var testDestination : String = "";
	public var testSource : String = "";

    var amount : Int;
	
    public function new(source, destination, amount) {
        this.source = source;
        this.destination = destination;
        this.amount = amount;
    }

    public function transfer() {
        this.source.withdraw();	
    }

    @role var source : {
        function decreaseBalance(a : Int) : Self;

		function addSource(a : Self) : Self {
			testSource += destination.namePublic;
			return a;
		}

		public function withdraw() {
            self.decreaseBalance(Std.int(amount / 2));
			// Testing RoleMethod access inside own role
			self.addSource(self).decreaseBalance(Std.int(amount / 2));
            destination.deposit();
		}		
	}

    @role var destination : {
        function increaseBalance(a : Int) : dci.Self;
		
		var name(default, null) : String;
		private var namePrivate(default, null) : String;
		public var namePublic(default, null) : String;
		
        public function deposit() {
            testDestination = self.increaseBalance(amount).name + namePublic + namePrivate;
        }
    }
}