package haxedci;

import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;

class Role
{
	public function new(field : Field) {
		if (field == null) throw "field cannot be null.";
		
		this.field = field;
		this.bound = null;
		this.type = switch field.kind {
			case FVar(t, _): t;
			case _: Context.error("Only var fields can be a Role.", field.pos);
		}
		this.roleMethods = get_roleMethods();
	}
	
	public var field(default, null) : Field;
	public var bound(default, default) : Null<Position>;
	public var type(default, null) : ComplexType;

	public var name(get, null) : String;
	function get_name() return field.name;

	private function incorrectTypeError() Context.error("A Role must have an anonymous structure as its RoleObjectContract. See http://haxe.org/manual/types-anonymous-structure.html for syntax.", field.pos);
	private function basicTypeError(name) Context.error(name + " is a basic type, only objects can play a Role in a Context. You can make it a normal field instead, or pass it as a parameter.", field.pos);

	public var roleMethods(default, null) : Map<String, RoleMethod>;
	function get_roleMethods() {
		var output = new Map<String, RoleMethod>();
		switch(field.kind) {
			case FVar(t, e): 
				
				if (t == null) incorrectTypeError();
					
				switch(t) {
					// Add Void to anonymous fields if it doesn't exist.
					case TAnonymous(fields): 
						for (f in fields) switch f.kind {
							case FFun(func) if (func.ret == null):
								if(Context.defined("dci-signatures-warnings"))
									Context.warning("RoleObjectContract without explicit return value", f.pos);
								
								func.ret = TPath( { sub: null, params: null, pack: [], name: "Void" } );
							case _:
						}

					case TPath( { name: "Int", pack: [], params: [] } ): basicTypeError("Int");
					case TPath( { name: "Bool", pack: [], params: [] } ): basicTypeError("Bool");
					case TPath( { name: "Float", pack: [], params: [] } ): basicTypeError("Float");
						
					case _: 
						incorrectTypeError();
				}
				
				if(e != null) switch e.expr {
					case EBlock(exprs): for(e in exprs) switch e.expr {
						case EFunction(name, f):
							if (name == null) Context.error("A RoleMethod must have a name.", e.pos);
							output.set(name, new RoleMethod(this, name, f));
						case _:
							Context.error("A Role can only contain simple functions as RoleMethods.", e.pos);
					}
					case _: 
						Context.error("A Role can only be assigned a block of RoleMethods.", e.pos);
				}
			case _:
				Context.error("Only var fields can be a Role.", field.pos);
		};
		return output;
	}
}
