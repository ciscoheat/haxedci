package haxedci;

import haxe.macro.Expr;

class RoleMethod
{
	var name(get, null) : String;
	function get_name() { return signature.name; };
	
	public var role : Role;
	public var func : Function;
	public var field : Field;
	var signature : Field;
	
	public function new(role : Role, name : String, func : Function) {
		this.role = role;
		this.func = func;

		this.signature = {
			kind: FFun({
				ret: func.ret,
				params: func.params,
				expr: null,
				args: func.args
			}),
			name: name,
			access: [],
			pos: func.expr.pos,
			meta: [],
			doc: null			
		};

		this.field = {
			pos: func.expr.pos,
			name: Role.roleMethodFieldName(role.name, name),
			meta: [{ pos: func.expr.pos, params: [], name: ":noCompletion" }],
			kind: FFun(func),
			doc: null,
			access: [APrivate]
		};
	}
}
