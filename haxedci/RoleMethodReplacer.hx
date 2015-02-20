package haxedci;

#if macro
import haxe.ds.Option;
import sys.io.File;
import sys.io.FileOutput;
import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.ExprTools;
using Lambda;

/**
 * Tests if roles are bound in the same function,
 * and replaces RoleMethod calls with its mangled representation.
 * i.e. this.console.cursor.pos => this.console__cursor.pos
 */
class RoleMethodReplacer
{
	public function new(role : Null<Role>, context : Dci) {
		this.context = context;
		this.role = role;
	}

	public function replace(field : Field) {
		switch(field.kind) {
			case FVar(_, e): if(e != null) e.iter(replaceField.bind(_, Option.None));
			case FFun(f): if(f.expr != null) f.expr.iter(replaceField.bind(_, Option.Some(f)));
			case FProp(_, _, _, e): if(e != null) e.iter(replaceField.bind(_, Option.None));
		}			
	}
	
	var role : Role;
	var context : Dci;
	
	function roles_bindRole(e : Expr, currentFunction : Option<Function>) {
		var fieldArray = extractIdentifier(e);
		if (fieldArray == null) return;
		if (fieldArray[0] == "this") fieldArray.shift();		
		if (fieldArray.length != 1)	return;
		
		var boundRole = context.roles.find(function(r) return r.name == fieldArray[0]);
		if (boundRole == null) return;
		
		// Set where the Role was bound in the Context.
		boundRole.bound = e.pos;

		switch(currentFunction) {
			case None: Context.error('Role must be bound in a Context method!', e.pos);
			case Some(f):
				if (context.roleBindMethod == null) {
					context.roleBindMethod = f;
					context.lastRoleBindPos = e.pos;
				}
				else if (context.roleBindMethod != f) {
					Context.warning(
						'All Roles in a Context must be assigned in the same function.', 
						context.lastRoleBindPos
					);
					Context.error('All Roles in a Context must be assigned in the same function.', e.pos);
				}
		}
	}
	
	/**
	 * Returns an array of identifiers from the current expression,
	 * or null if the expression isn't an EField or EConst.
	 */
	function extractIdentifier(e : Expr) {
		var fields = [];
		while (true) {
			switch(e.expr) {
				case EField(e2, field):
					var replace = (role != null && field == Role.SELF) ? role.name : field;
					fields.unshift(replace);
					e = e2;

				case EConst(CIdent(s)):
					var replace = (role != null && s == Role.SELF) ? role.name : s;
					fields.unshift(replace);
					return fields;

				case _:	return null;
			}
		}
	}

	function replaceField(e : Expr, currentFunction : Option<Function>) {
		switch(e.expr) {
			case EFunction(name, f) if(f.expr != null): replaceField(f.expr, Some(f)); return;
			case EBinop(OpAssign, e1, e2): roles_bindRole(e1, currentFunction);
			case EField(_, _): if (replaceIdentifiers(e)) return;				
			case _:
		}

		e.iter(replaceField.bind(_, currentFunction));
	}
	
	function replaceIdentifiers(e : Expr) {
		var fieldArray = extractIdentifier(e);
		if (fieldArray == null) return false;
		
		// Given that console is a Role, rewriting 
		// [this, console, cursor, pos] to [this, console__cursor, pos]
		//trace(fieldArray);

		var newArray = [];
		var skip = false;
		var length = fieldArray.length;

		for (i in 0...length) {
			if (skip) {
				skip = false;
				continue;
			}
			
			var field = fieldArray[i];
			if (i > length - 2) {
				newArray.push(field);
			} else {
				// Test if a Role is matching the field.
				var matchingRole = context.roles.get(field);
				if (matchingRole != null && matchingRole.roleMethods.exists(fieldArray[i + 1])) {
					newArray.push(Role.roleMethodFieldName(fieldArray[i], fieldArray[i+1]));
					skip = true; // Skip next field since it's now a part of the Role method call.
				} else {
					newArray.push(field);
				}
			}
		}
		
		if (fieldArray.length != newArray.length) {
			e.expr = buildField(newArray, newArray.length - 1, e.pos);
			return true;
		}
		
		return false;
	}
	
	function buildField(identifiers, i, pos) {
		if (i > 0)
			return EField({expr: buildField(identifiers, i - 1, pos), pos: pos}, identifiers[i]);
		else
			return EConst(CIdent(identifiers[i]));
	}

}
#end
