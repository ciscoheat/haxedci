package dci;
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;

#if macro	
private typedef RoleMap = Map<String, Array<String>>;

class Dci
{
	@macro public static function context() : Array<Field>
	{
		var fields : Array<Field> = Context.getBuildFields();
		var hasRole = function(m) { return m.name == "role"; };
		
		//trace("Context: " + Context.getLocalClass());
		
		var roleFields = [];
		var nonRoleFields = [];
		var roleMethods = new RoleMap();
		
		// First pass: Add Roles
		for (field in fields)
		{
			//if (Lambda.exists(field.meta, function(m) { return m.name == "dump"; } )) trace(field);
			
			if (Lambda.exists(field.meta, hasRole))
				addRole(field, roleFields);
			else
				nonRoleFields.push(field);
		}
		
		// Second pass: Add Role methods
		for (field in fields)
		{
			if (Lambda.exists(field.meta, hasRole))
				addRoleMethods(field, roleFields, roleMethods);
		}
		
		// Third pass: Replace function calls with Role method calls, where appropriate		
		for (field in fields)
		{
			var isRole = Lambda.exists(field.meta, hasRole);
			
			var ex : Expr;
			switch(field.kind)
			{
				case FVar(_, e): ex = e;					
				case FFun(f): ex = f.expr;
				case FProp(_, _, _, e): ex = e;
			}
			
			if (ex != null)
				ex.iter(function(e) { replaceRoleMethodCalls(e, roleMethods, isRole ? field.name : null); });
		}
		
		return roleFields.concat(nonRoleFields);
	}
	
	// Replace Role method calls with the transformed version.
	// TODO: It's optimized for speed, but could make it a bit nicer.
	private static function replaceRoleMethodCalls(e : Expr, roleMethods : RoleMap, roleName : String)
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
						if (i > length-2 || !roleMethods.exists(field) || !Lambda.has(roleMethods[field], fieldArray[i + 1]))
						{
							newArray.push(field);
							continue;
						}
						
						var roleMethod = roleMethodName(field, fieldArray[i + 1]);
						//trace("Role method call: " + roleMethod + " at " + e.pos);
						newArray.push(roleMethod);					
						skip = true; // Skip next field since it's now a part of the Role method call.
					}
					
					if (fieldArray.length != newArray.length)
					{
						// Parse the final field and replace the old one.
						e.expr = Context.parse(newArray.join("."), e.pos).expr;
						return;
					}					
				}
				
			case _: 
		}
		
		e.iter(function(e) { replaceRoleMethodCalls(e, roleMethods, roleName); });
	}
	
	// Extract the field to an array. this.test.length = ['this', 'test', 'length']
	// Also replace "self" with the roleName if set.
	private static function extractField(e : Expr, roleName : String)
	{
		var output = [];
		while (true)
		{
			switch(e.expr)
			{
				case EField(e2, field):
					var replace = (roleName != null && field == 'self') ? roleName : field;
					output.unshift(replace);
					e = e2;
				
				case EConst(c):
					switch(c)
					{
						case CIdent(s):
							var replace = (roleName != null && s == 'self') ? roleName : s;
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
	
	private static function addRole(field : Field, output : Array<Field>)
	{
		if (field.name.toLowerCase() == 'self')
			Context.error('A Role cannot have the name "self", it is used as an accessor within RoleMethods.', field.pos);
		
		var errorMsg = "Incorrect Role definition: Must be a static var.";
		var error = function(p) { Context.error(errorMsg, p); };
		
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
							output.push(contextField(FVar(TPath(p)), field.name, [APrivate], field.pos));
							return;
						case _: error(field.pos);
					}
				}
				else
				{
					switch(e.expr)
					{
						// This role is defined using a block, so search for a RoleInterface.
						case EBlock(exprs):
							for (expr in exprs)
							{
								switch(expr.expr)
								{
									case EVars(vars):
										for (v in vars)
										{
											if (v.name.toLowerCase() == "roleinterface")
											{
												switch(v.type)
												{
													case TAnonymous(fields):
														//trace("Adding Role " + field.name + " with RoleInterface");
														output.push(contextField(FVar(TAnonymous(fields)), field.name, [APrivate], expr.pos));
														return;
														
													case TPath(p):
														// Simple RoleInterface, just a type.
														//trace("Adding Role: " + field.name + " with simple RoleInterface");
														output.push(contextField(FVar(TPath(p), null), field.name, [APrivate], expr.pos));
														return;
														
													case _: Context.error("RoleInterfaces must be defined as a Type or with class notation according to http://haxe.org/manual/struct#class-notation", expr.pos);
												}												
											}
										}										
										
									case _:
								}
							}
							
							// No RoleInterface found, add the field as Dynamic.
							//trace("Adding Role " + field.name + " as Dynamic");
							output.push(contextField(FVar(TPath( { name: 'Dynamic', pack: [], params: [] } ), null), field.name, [APrivate], e.pos));
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
	
	private static function addRoleMethods(field : Field, output : Array<Field>, methods : RoleMap)
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
									var methodName = roleMethodName(field.name, name);
									var noCompletion = { pos: f.expr.pos, params: [], name: ":noCompletion" };
									//trace("Adding role method: " + methodName);
									output.push(contextField(FFun(f), methodName, [APrivate], f.expr.pos, [noCompletion]));
									
									if (!methods.exists(field.name))
										methods.set(field.name, []);
										
									methods[field.name].push(name);									
									addSelfToMethod(f, field.name);
									
								case _:
							}
						}
						
					case _: error(e.pos);
				}
					
			case _: error(field.pos);
		}		
	}
	
	private static function addSelfToMethod(f : Function, roleName : String)
	{
		switch(f.expr.expr)
		{
			case EBlock(exprs):
				exprs.unshift(macro var self = this.$roleName);
				
			case _:
		}
	}
}
#end
