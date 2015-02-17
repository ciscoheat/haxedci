package haxedci;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
using Lambda;

class Dci
{
	@macro public static function context() : Array<Field>
	{
		return new Dci().execute();
	}

	/**
	 * Class field name => Role
	 */
	public var roles(default, null) : Map<String, Role>;
	
	/**
	 * RoleMethod field => Role
	 */
	public var roleMethodAssociations(default, null) : Map<Field, Role>;

	/**
	 * Last role bind function, to test role binding errors.
	 */
	public var roleBindMethod : Function;

	/**
	 * Last role bind position, in case of a role binding error.
	 */
	public var lastRoleBindPos : Position;
	
	var fields : Array<Field>;

	public function new()
	{
		fields = Context.getBuildFields();
		roles = new Map<String, Role>();
		roleMethodAssociations = new Map<Field, Role>();
		
		for (f in fields.filter(Role.isRoleField))
			roles.set(f.name, new Role(f, this));
	}

	public function execute() : Array<Field>
	{
		var outputFields = [];

		trace("======== Context: " + Context.getLocalClass());

		// Loop through fields again to avoid putting them in incorrect order.
		for (field in fields) {
			var role = roles.get(field.name);
			if (role != null) {
				role.addFields(outputFields);
			}
			else {
				outputFields.push(field);
			}
		}

		for (field in outputFields) {
			var role = roleMethodAssociations.get(field);
			//trace(field.name + " has role " + (role == null ? '<no role>' : role.name));
			new RoleMethodReplacer(field, roleMethodAssociations.get(field), this).replace();
		}

		if (!Context.defined("display")) {
			// Test if all roles were bound.
			for (role in roles) if (role.bound == null)
				Context.warning("Role " + role.name + " isn't bound in this Context.", role.field.pos);			
		}
		
		/*
		for (role in roles)	{
			// Could fix possible autocompletion problem:
			//if (role.methods == null) continue;
		}
		*/

		return outputFields;
	}
}

// ----------------------------------------------------------------------------------------------

	/*
	// The reverse of extractField.
	static function buildField(identifiers, i, pos)	{
		if (i > 0)
			return EField({expr: buildField(identifiers, i - 1, pos), pos: pos}, identifiers[i]);
		else
			return EConst(CIdent(identifiers[i]));
	}
	*/

	/*
	// Special trick for autocompletion: At runtime, only objects that fulfill the RoleObjectContract
	// should be bound to a Role. When compiling however, it is convenient to also have the RoleMethods
	// displayed. Therefore, test if we're in autocomplete mode, add the RoleMethods if so.
	function mergeTypeAndRoleObjectContract(role : Role, type : TypePath) : ComplexType
	{
		if (Context.defined("display"))
		{
			// Can only extend classes and structures, so test if type is one of those.
			var realType = haxe.macro.Context.getType(type.name);
			if (realType == null) return TPath(type);
			switch(realType)
			{
				case TMono(_), TLazy(_), TFun(_, _), TEnum(_, _), TDynamic(_), TAbstract(_, _):
					return TAnonymous(roleMethodsList(role));
				case _:
			}
			// Creates a compile error if RoleObjectContract field exists on the type, which is useful.

			#if (haxe_ver >= 3.1)
			return TExtend([type], roleMethodsList(role));
			#else
			return TExtend(type, roleMethodsList(role));
			#end
		}

		return TPath(type);
	}

	// Same trick here as above.
	function mergeAnonymousInterfaces(role : Role, fields : Array<Field>) : ComplexType
	{
		if (Context.defined("display"))
		{
			// Test if there are RoleObjectContract/Method name collisions
			var hash = new Map<String, Field>();
			for (field in fields) hash[field.name] = field;

			for (method in role.methods.keys())
			{
				if (hash.exists(method))
					Context.error('The RoleObjectContract field "' + hash[method].name + '" has the same name as a RoleMethod.', hash[method].pos);
			}

			return TAnonymous(fields.concat(roleMethodsList(role)));
		}

		return TAnonymous(fields);
	}

	function roleMethodsList(role : Role) : Array<Field>
	{
		var output = new Array<Field>();

		for (roleName in role.methods.keys())
		{
			var m = role.methods.get(roleName);
			switch(m.kind)
			{
				case FFun(f):
					if (f.ret != null)
					{
						// There cannot be a body for the function because we're only creating a field definition,
						// so a new definition needs to be created.
						var functionDef = {
							ret: f.ret,
							params: f.params,
							expr: null,
							args: f.args
						}

						output.push(contextField(FFun(functionDef), roleName, [], f.expr.pos));
					}
				case _:
					Context.error("Incorrect RoleMethod definition: Must be a function.", m.pos);
			}
		}
		return output;
	}

	// Add a Role object to roles.
	function addRole(field : Field)
	{
		if (field.name == SELF)
			Context.error('A Role cannot be named "$SELF", it is used as an accessor within RoleMethods.', field.pos);
		else if (field.name == "Context") // Reserved for diagrams.
			Context.error('A Role cannot be named "Context".', field.pos);

		var error = function(p) { Context.error("Incorrect Role definition: Must be a var.", p); };
		var role = new Role(contextField(null, field.name, [APrivate], field.pos));

		var addRoleObjectContract = function(fieldType, pos)
		{
			switch(fieldType)
			{
				case TAnonymous(fields):
					//trace("Adding Role " + field.name + " with RoleObjectContract");
					role.field.kind = FVar(mergeAnonymousInterfaces(role, fields));
					return true;

				case TPath(p):
					//trace("Adding Role " + field.name + " with Type as RoleObjectContract: " + p);
					role.field.kind = FVar(mergeTypeAndRoleObjectContract(role, p));
					return true;

				case _:
					Context.error("RoleObjectContracts must be defined as a Type or with class notation according to http://haxe.org/manual/struct#class-notation", pos);
					return false;
			}
		};

		switch(field.kind)
		{
			case FVar(t, e):
				if (t != null && e == null)
				{
					// Add a simple role definition, like:
					// @role static var amount : Float
					switch(t)
					{
						case TPath(p):
							//trace("Adding Role " + field.name + " with only a type");
							role.field.kind = FVar(mergeTypeAndRoleObjectContract(role, p));
						case TAnonymous(fields):
							//trace("Adding Role " + field.name + " with an anonymous type");
							role.field.kind = FVar(mergeAnonymousInterfaces(role, fields));
						case _:
							error(field.pos);
					}
				}
				else
				{
					switch(e.expr)
					{
						// The Role is defined using a block.
						case EBlock(exprs):

							// First, find and extract the RoleMethods
							for (expr in exprs)
							{
								switch(expr.expr)
								{
									case EFunction(name, f):
										//trace("Adding RoleMethod " + name + " for Role " + field.name);
										var methodName = roleMethodName(field.name, name);
										var noCompletion = { pos: f.expr.pos, params: [], name: ":noCompletion" };
										var roleField = contextField(FFun(f), methodName, [APrivate], f.expr.pos, [noCompletion]);

										if(role.methods != null)
											role.methods.set(name, roleField);

										//if(f.ret == null)
										//	haxe.macro.Context.warning("The RoleMethod " + field.name + "." + name + " has no return type, add it if you need autocompletion.", expr.pos);

									case _:
								}
							}

							var found = false;

							// Then create the Role with its RoleObjectContract based on the RoleMethods.
							if (t == null)
							{
								for (expr in exprs)	switch expr.expr
								{
									case EVars(vars):
										for (v in vars)
										{
											if (v.name == ROLEINTERFACE)
											{
												Context.warning('Using "roleInterface" is deprecated, define the type directly on the class variable instead.', expr.pos);
												found = addRoleObjectContract(v.type, expr.pos);
											}
											else
											{
												Context.error("The only variable that can exist in a Role definition must be named \"" + ROLEINTERFACE + "\".", expr.pos);
											}
										}

									case _:
								}
							}
							else
							{
								found = addRoleObjectContract(t, field.pos);
							}

							if (!found)
							{
								//trace("No RoleObjectContract found, adding Role '" + field.name + "' as Dynamic");
								role.field.kind = FVar(TPath({ name: 'Dynamic', pack: [], params: [] }));
							}

						case _: error(e.pos);
					}
				}

			case _: error(field.pos);
		}

		// Some autocomplete problem forces this
		if (roles == null) roles = new Roles();

		roles.set(field.name, role);
	}

	private static function contextField(kind : FieldType, name : String, access : Array<Access>, pos : Position, meta : Array<MetadataEntry> = null) : Field
	{
		if (meta == null) meta = [];

		var output = {
			pos: pos,
			name: name,
			meta: meta,
			kind: kind,
			doc: null,
			access: access
		};

		return output;
	}

	private static function roleMethodName(role : String, method : String)
	{
		return role + "__" + method;
	}

	function addSelfToMethods(field : Field)
	{
		var errorMsg = "Incorrect RoleMethod definition: Must be a block or a Type.";
		var error = function(p) { Context.error(errorMsg, p); };

		switch(field.kind)
		{
			case FVar(t, e):
				if (t != null) return;

				switch(e.expr)
				{
					case EBlock(exprs):
						for (expr in exprs)
						{
							switch(expr.expr)
							{
								case EFunction(name, f):
									addSelfToMethod(f, field.name);

								case _:
							}
						}

					case _: error(e.pos);
				}

			case _: error(field.pos);
		}
	}

	function addSelfToMethod(f : Function, roleName : String)
	{
		switch(f.expr.expr)
		{
			case EBlock(exprs):
				exprs.unshift(macro var $SELF = this.$roleName);
				exprs.unshift(macro var $CONTEXT = this);
			case _:
				f.expr = {expr: EBlock([f.expr]), pos: f.expr.pos};
				addSelfToMethod(f, roleName);
		}
	}
	*/
#end
