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
	/**
	 * Last role bind function, to test role binding errors.
	 */
	var roleBindFunction : Function;

	var context : Dci;

	public function new(context : Dci) {
		this.context = context;
	}

	public function replace(field : Field, role : Option<Role>) {
		switch(field.kind) {
			case FVar(_, e): if(e != null) e.iter(replaceInExpr.bind(_, role, Option.None));
			case FFun(f): if(f.expr != null) f.expr.iter(replaceInExpr.bind(_, role, Option.Some(f)));
			case FProp(_, _, _, e): if(e != null) e.iter(replaceInExpr.bind(_, role, Option.None));
		}			
	}

	function replaceInExpr(e : Expr, role : Option<Role>, currentFunction : Option<Function>) {
		switch(e.expr) {
			case EFunction(name, f) if(f.expr != null): replaceInExpr(f.expr, role, Some(f)); return;
			case EField(_, _): if (replaceIdentifiers(e, role)) return;
			case EBinop(OpAssign, e1, e2): setRoleBindPos(e1, role, currentFunction);
			case _:
		}

		e.iter(replaceInExpr.bind(_, role, currentFunction));
	}
	
	function setRoleBindPos(e : Expr, role : Option<Role>, currentFunction : Option<Function>) {
		var fieldArray = extractIdentifier(e, role);
		if (fieldArray == null) return;
		if (fieldArray[0] == "this") fieldArray.shift();
		if (fieldArray.length != 1)	return;
		
		var boundRole = context.roles.find(function(r) return r != null && r.name == fieldArray[0]);
		if (boundRole == null) return;

		// Set where the Role was bound in the Context.
		boundRole.bound = e.pos;

		switch(currentFunction) {
			case None: Context.error('Role must be bound in a Context method!', e.pos);
			case Some(f):
				if (roleBindFunction == null) {
					roleBindFunction = f;					
				}
				else if (roleBindFunction != f) {
					Context.warning(
						'All Roles in a Context must be assigned in the same function.', 
						roleBindFunction.expr.pos
					);
					Context.error(
						'All Roles in a Context must be assigned in the same function.', 
						e.pos
					);
				}
		}
	}
	
	/**
	 * Returns an array of identifiers from the current expression,
	 * or null if the expression isn't an EField or EConst.
	 */
	function extractIdentifier(e : Expr, role : Option<Role>) : Null<Array<String>> {
		var fields = [];
		while (true) {
			switch(e.expr) {
				case EField(e2, field):
					var replace = switch(role) {
						case None: field;
						case Some(r): field == Role.SELF ? r.name : field;
					}
					fields.unshift(replace);
					e = e2;

				case EConst(CIdent(s)):
					var replace = switch(role)	{
						case None: s;
						case Some(r): s == Role.SELF ? r.name : s;
					}
					fields.unshift(replace);
					return fields;

				case _:	
					return null;
			}
		}
	}

	function replaceIdentifiers(e : Expr, role : Option<Role>) {
		var fieldArray = extractIdentifier(e, role);
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
				var matchingRole = context.roles.find(function(r) return r != null && r.name == field);

				if (matchingRole != null && matchingRole.roleMethods.exists(fieldArray[i + 1])) {
					newArray.push(Role.roleMethodFieldName(fieldArray[i], fieldArray[i+1]));
					skip = true; // Skip next field since it's now a part of the Role method call.
				} else {
					newArray.push(field);
				}
			}
		}
		
		if (fieldArray.length != newArray.length) {
			e.expr = (macro $p{newArray}).expr;
			return true;
		}
		
		return false;
	}	
}
#end
