package haxedci;

#if macro
import haxe.macro.Type;
import haxe.macro.Expr;
import haxe.macro.Context;

using Lambda;
using haxe.macro.MacroStringTools;
using haxe.macro.ComplexTypeTools;

class RoleObjectContractTypeMerger
{
	var complexType : ComplexType;
	var role : Role;

	public function new(role : Role) {
		this.role = role;
		
		switch(role.field.kind) {
			case FVar(t, _): this.complexType = t;
			case _: Context.error("Only var fields can be a Role.", role.field.pos);
		}
	}
	
	public function mergedType() : ComplexType {
		return type_mergeWithRole();
	}
	
	function type_mergeWithRole() : ComplexType {
		//trace('----- Merging type and RoleObjectContract "${role.field.name}"');
		
		switch(complexType) {
			case TAnonymous(fields):
				//trace("TAnonymous, merge with RoleObjectContract.");
				return mergeAnonymousInterfaces(fields);

			case TPath(p):
				//trace('TPath: ' + p.pack.toDotPath(p.name));
				return mergeTypeAndRoleObjectContract(complexType.toType(), p);

			case _:
				// If in display mode, the type is merged and should be displayed.
				if (Context.defined("display")) return complexType;
				
				// If not in display mode, the type isn't properly defined.
				Context.error("RoleObjectContracts must be defined as a Type or with class " + 
				"notation according to http://haxe.org/manual/struct#class-notation", role.field.pos);
				return null;
		}
	}
	
	function mergeTypeAndRoleObjectContract(type : Type, typePath : TypePath) : ComplexType {		
		// Can only extend classes and structures, so test if type is one of those.
		if(type != null) switch(type) {
			case TMono(_), TLazy(_), TFun(_, _), TEnum(_, _), TDynamic(_), TAbstract(_, _):
				//trace("Not a class or structure, using RoleObjectContract only.");
				return TAnonymous(role_typeDef());
			case TType(t, _):
				return mergeTypeAndRoleObjectContract(Context.follow(t.get().type), typePath);
			case TAnonymous(_):
			case TInst(_, _):
				/*
				var instType = ct.get();
				typePath = typePath != null ? typePath : {
					sub: null,
					params: instType.params.map(function(tp) return TPType(Context.toComplexType(tp.t))),
					pack: instType.pack,
					name: instType.name
				};
				*/
		}
		
		var roleMethods = role_typeDef();
		if (roleMethods.length == 0) return TPath(typePath);
		
		// Creates a compile error if RoleObjectContract field exists on the type, 
		// which is useful since it's not allowed.
		#if (haxe_ver >= 3.1)
		return TExtend([typePath], roleMethods);
		#else
		return TExtend(typePath, roleMethods);
		#end
	}

	function mergeAnonymousInterfaces(fields : Array<Field>) : ComplexType {
		// Test if there are RoleObjectContract/Method name collisions
		var hash = new Map<String, Field>();
		for (field in fields) hash[field.name] = field;

		for (method in role.roleMethods.keys())
		{
			if (hash.exists(method)) {
				Context.error('The RoleObjectContract field "' + hash[method].name + 
				'" has the same name as a RoleMethod.', hash[method].pos);
			}
		}

		return TAnonymous(fields.concat(role_typeDef()));
	}

	function role_typeDef() : Array<Field> {
		var output = Dci.rmSignatures.get(role.context.name + '-' + role.name);
		return output == null ? [] : output;
	}
}
#end
