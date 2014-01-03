package dci;
import haxe.crypto.Adler32;
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;

#if macro
// A map for detecting role names. Role => [RoleMethod, ...]
private typedef RoleNameMap = Map<String, Array<String>>;

// A map for the RoleMethods, used when adding 'self'.
private typedef RoleMap = Map<String, Array<Function>>;

// A map for the types of the RoleMethod functions.
private typedef RoleInterfaceList = Map<String, Array<Field>>;

// The final RoleInterface type, an anonymous type with or without an extension.
private typedef RoleInterfaces = Map<String, ComplexType>;

class Dci
{
	@macro public static function context() : Array<Field>
	{
		return new Dci().execute();
	}

	private static var SELF = "self";
	private static var ROLEINTERFACE = "roleInterface";

	var roleFields : Array<Field>;
	var nonRoleFields : Array<Field>;
	var roleMethodNames : RoleNameMap;
	var roleMethods : RoleMap;
	var roleInterfaceList : RoleInterfaceList;
	var roleInterfaces : RoleInterfaces;
	
	public function new()
	{
		roleFields = [];
		nonRoleFields = [];
		roleMethodNames = new RoleNameMap();
		roleMethods = new RoleMap();
		roleInterfaceList = new RoleInterfaceList();
		roleInterfaces = new RoleInterfaces();
	}
	
	public function execute() : Array<Field>
	{
		//trace("Context: " + Context.getLocalClass());
			
		var fields = Context.getBuildFields();

		// First pass: Add Role methods and create the RoleInterfaces map.
		for (field in fields)
		{
			addRoleMethods(field);
		}

		// Second pass: Add Roles.
		for (field in fields)
		{
			if(hasRole(field)) addRole(field);
		}
		
		// Third pass: Replace function calls with Role method calls, where appropriate		
		for (field in fields)
		{
			var isRole = hasRole(field);
			
			var ex : Expr;
			switch(field.kind)
			{
				case FVar(_, e): ex = e;					
				case FFun(f): ex = f.expr;
				case FProp(_, _, _, e): ex = e;
			}
			
			if (ex != null)
				ex.iter(function(e) { replaceRoleMethodCalls(e, isRole ? field.name : null); } );
				
			if (!isRole)
				nonRoleFields.push(field);
		}
		
		for (roleName in roleMethods.keys())
		{
			for (roleMethod in roleMethods[roleName])
			{
				addSelfToMethod(roleMethod, roleName, roleMethod.expr.pos);
			}
		}
		
		return roleFields.concat(nonRoleFields);
	}

	static function hasRole(field : Field)
	{
		return Lambda.exists(field.meta, function(m) { return m.name == "role"; } );
	}

	// Replace Role method calls with the transformed version.
	// TODO: It's optimized for speed, but could make it a bit nicer.
	// TODO: Detect role method reference and 'self' reference, and act accordingly.
	function replaceRoleMethodCalls(e : Expr, roleName : String)
	{
		switch(e.expr)
		{
			case EField(e3, fd):
				var fieldArray = extractField(e, roleName);
				if (fieldArray != null)
				{
					var newArray = [];
					var skip = false;
					var length = fieldArray.length;
					
					for (i in 0 ... length)
					{
						if (skip)
						{
							skip = false;
							continue;
						}
						
						// Test if we're past the end of array (no need to check last field),
						// or if a Role is matching the field.
						var field = fieldArray[i];
						if (i > length-2 || !roleMethodNames.exists(field) || !Lambda.has(roleMethodNames[field], fieldArray[i + 1]))
						{
							newArray.push(field);
							continue;
						}
						
						var roleMethod = roleMethodName(field, fieldArray[i + 1]);						
						newArray.push(roleMethod);
						skip = true; // Skip next field since it's now a part of the Role method call.
					}
					
					if (fieldArray.length != newArray.length)
					{
						//trace("Role method call: " + newArray.join(".") + " at " + e.pos);
						e.expr = buildField(newArray, newArray.length - 1, e.pos);
						return;
					}					
				}
				
			case _: 
		}
		
		e.iter(function(e) { replaceRoleMethodCalls(e, roleName); });
	}

	// Extract the field to an array. this.test.length = ['this', 'test', 'length']
	// Also replace "self" with the roleName if set.
	static function extractField(e : Expr, roleName : String)
	{
		var output = [];
		while (true)
		{
			switch(e.expr)
			{
				case EField(e2, field):
					var replace = (roleName != null && field == SELF) ? roleName : field;
					output.unshift(replace);
					e = e2;
				
				case EConst(c):
					switch(c)
					{
						case CIdent(s):
							var replace = (roleName != null && s == SELF) ? roleName : s;
							output.unshift(replace);
							//trace(output);
							return output;
							
						case _:
							return null;
					}
					
				case _:
					return null;
			}
		}
	}
	
	// The reverse of extractField.
	static function buildField(identifiers, i, pos)
	{
		if (i > 0)
			return EField({expr: buildField(identifiers, i - 1, pos), pos: pos}, identifiers[i]);
		else
			return EConst(CIdent(identifiers[i]));
	}
	
	// Special trick for autocompletion: At runtime, only objects that fulfill the RoleInterface
	// should be bound to a Role. When compiling however, it is convenient to also have the RoleMethods
	// displayed. Therefore, test if we're in autocomplete mode, add the RoleMethods if so.
	function mergeTypeAndRoleInterface(fieldName : String, type : TypePath) : ComplexType
	{
		if (Context.defined("display") && roleInterfaceList.exists(fieldName))
		{
			return TExtend(type, roleInterfaceList[fieldName]);
		}

		return TPath(type);
	}

	// Same trick here as above.
	function mergeAnonymousInterfaces(fieldName : String, fields : Array<Field>) : ComplexType
	{
		if (Context.defined("display") && roleInterfaceList.exists(fieldName))
		{
			return TAnonymous(fields.concat(roleInterfaceList[fieldName]));
		}

		return TAnonymous(fields);
	}
	
	//function mergedRoleInterface(fieldName : String

	function addRole(field : Field)
	{
		if (field.name == SELF)
			Context.error('A Role cannot be named "$SELF", it is used as an accessor within RoleMethods.', field.pos);
		
		var error = function(p) { Context.error("Incorrect Role definition: Must be a var.", p); };
		
		switch(field.kind)
		{
			case FVar(t, e): 
				if (t != null)
				{
					// Add a simple role definition, like: 
					// @role static var amount : Float
					switch(t)
					{
						case TPath(p): 
							//trace("Adding Role " + field.name + " with only a type");
							var fieldType = mergeTypeAndRoleInterface(field.name, p);
							roleFields.push(contextField(FVar(fieldType), field.name, [APrivate], field.pos));
							roleInterfaces[field.name] = fieldType;
							return;
						case _: error(field.pos);
					}
				}
				else
				{
					switch(e.expr)
					{
						// The role is defined using a block, so search for a RoleInterface.
						case EBlock(exprs):
							for (expr in exprs)
							{
								switch(expr.expr)
								{
									case EVars(vars):
										for (v in vars)
										{
											if (v.name == ROLEINTERFACE)
											{
												switch(v.type)
												{
													case TAnonymous(fields):
														//trace("Adding Role " + field.name + " with RoleInterface");
														var fieldType = mergeAnonymousInterfaces(field.name, fields);
														roleFields.push(contextField(FVar(fieldType), field.name, [APrivate], expr.pos));
														roleInterfaces[field.name] = fieldType;
														return;
														
													case TPath(p):
														//trace("Adding Role: " + field.name + " with simple RoleInterface");
														var fieldType = mergeTypeAndRoleInterface(field.name, p);
														roleFields.push(contextField(FVar(fieldType), field.name, [APrivate], expr.pos));
														roleInterfaces[field.name] = fieldType;
														return;
														
													case _: Context.error("RoleInterfaces must be defined as a Type or with class notation according to http://haxe.org/manual/struct#class-notation", expr.pos);
												}												
											}
										}										
										
									case _:
								}
							}
							
							//trace("No RoleInterface found, adding Role " + field.name + " as Dynamic");
							roleFields.push(contextField(FVar(TPath( { name: 'Dynamic', pack: [], params: [] } ), null), field.name, [APrivate], e.pos));
							return;
							
						case _: error(e.pos);
					}
				}
					
			case _: error(field.pos);
		}		
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
		var errorMsg = "Incorrect Role method definition: Must be a block or a Type.";
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
									addSelfToMethod(f, field.name, f.expr.pos);
									
								case _:
							}
						}
						
					case _: error(e.pos);
				}
					
			case _: error(field.pos);
		}		
	}
	
	function addRoleMethods(field : Field)
	{
		if (!hasRole(field)) return;
		
		var errorMsg = "Incorrect Role method definition: Must be a block or a Type.";
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
									var methodName = roleMethodName(field.name, name);
									var noCompletion = { pos: f.expr.pos, params: [], name: ":noCompletion" };
									//trace("Adding role method: " + methodName);
									roleFields.push(contextField(FFun(f), methodName, [APrivate], f.expr.pos, [noCompletion]));
																		
									// Store the RoleMethod for usage in next passes
									if (!roleMethodNames.exists(field.name))
									{
										roleMethodNames.set(field.name, []);
										roleMethods.set(field.name, []);
									}

									roleMethodNames[field.name].push(name);
									roleMethods[field.name].push(f);
									
									// Autocompletion can only display when the return type is known, 
									// so only define the RoleInterface if it is set.
									if (f.ret != null)
									{
										if (!roleInterfaceList.exists(field.name))
											roleInterfaceList.set(field.name, []);
										
										// There cannot be a body for the function because we're only creating a field definition,
										// so a new definition needs to be created.
										var functionDef = {
											ret: f.ret,
											params: f.params,
											expr: null,
											args: f.args
										}
										
										roleInterfaceList[field.name].push(contextField(FFun(functionDef), name, [], f.expr.pos));
									}
									
								case _:
							}
						}
						
					case _: error(e.pos);
				}
					
			case _: error(field.pos);
		}					
	}
	
	function addSelfToMethod(f : Function, roleName : String, pos : Position)
	{
		var type = roleInterfaces.exists(roleName) ? roleInterfaces[roleName] : null;
				
		switch(f.expr.expr)
		{
			case EBlock(exprs): exprs.unshift(macro var $SELF = this.$roleName);				
			case _:
		}
	}
}
#end
