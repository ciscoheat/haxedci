package haxedci;

import haxe.macro.Expr;

class RoleMethod
{
	public static var roleAccessor = "port";

	public static function mangledFieldName(roleName : String, roleMethod : String)	{
		return roleName + "__" + roleMethod;
	}

	public var name(get, null) : String;
	function get_name() return signature.name;
	
	public var role : Role;
	public var method : Function;
	public var field : Field;

	var signature : Field;
	
	public function new(role : Role, name : String, method : Function) {
		this.role = role;
		this.method = method;

		this.signature = {
			kind: FFun({
				ret: method.ret,
				params: method.params,
				expr: null,
				args: method.args
			}),
			name: name,
			access: [],
			pos: method.expr.pos,
			meta: [],
			doc: null			
		};

		this.field = {
			pos: method.expr.pos,
			name: mangledFieldName(role.name, name),
			meta: [{ pos: method.expr.pos, params: [], name: ":noCompletion" }],
			kind: FFun(method),
			doc: null,
			access: [APrivate]
		};
	}
}
