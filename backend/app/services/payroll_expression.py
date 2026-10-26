"""Pay component expressions: parsed with Python's ast module and evaluated over a whitelist.

An expression is arithmetic over references in braces, as the expression builder writes them:
    {gross_salary} / {applicable_days} * ({absent_days} + {half_days} * 0.5)
A reference is a system variable (SYSTEM_VARIABLES), a pay item or a formula, written as its name in
lower case with anything but letters and digits turned into "_" ("House Rent" -> {house_rent}).

Allowed: numbers, + - * / % **, parentheses, comparisons, and / or / not, `a if cond else b`, and the
functions min, max, round, floor, ceil, abs, if(cond, a, b). Nothing else parses: no attribute access, no
subscripts, no bare names, no strings, no lambdas, no keyword arguments. Arithmetic is done in Decimal.
"""
import ast
import re
from collections.abc import Callable, Mapping
from decimal import ROUND_CEILING, ROUND_FLOOR, ROUND_HALF_UP, Decimal, DivisionByZero, InvalidOperation

# Variables the run fills for every person. Pay items and formulas may not take these names.
SYSTEM_VARIABLES: dict[str, str] = {
    "gross_salary": "Monthly salary from the latest salary revision",
    "month_days": "Calendar days in the payroll month",
    "applicable_days": "Days the month is paid on: actual days, or the payroll's fixed days",
    "employed_days": "Days of the month the person was employed (joining and leaving prorate)",
    "worked_days": "Employed days less absences, half days (as half) and unpaid leave",
    "present_days": "Days marked present, work from home or official visit",
    "absent_days": "Days marked absent",
    "half_days": "Days marked half day",
    "short_days": "Days marked short day",
    "holiday_days": "Holidays, weekends and rest days",
    "leave_days": "Approved leave days in the month",
    "unpaid_leave_days": "Approved leave days of deductible leave types",
    "late_days": "Days with a late arrival",
    "late_minutes": "Minutes late, all month",
    "early_left_days": "Days left early",
    "early_left_minutes": "Minutes left early, all month",
    "short_minutes": "Late plus early-left minutes",
    "overtime_minutes": "Overtime minutes from the time sheet",
    "worked_minutes": "Minutes worked, all month",
    "expected_minutes": "Minutes the shifts expected, all month",
    "day_minutes": "Minutes in a working day (the shift's, or 480)",
    "penalty_days": "Warning penalties as days (100% = 1 day)",
    "loan_installment": "Loan installments due this month",
    "leave_encashment": "Leave encashment paid through this payroll",
    "service_months": "Whole months since joining",
    "branch_id": "The person's branch id", "department_id": "The person's department id",
    "designation_id": "The person's designation id", "grade_id": "The person's grade id",
    "employment_type_id": "The person's employment type id", "employee_group_id": "The person's employee group id",
    "location_id": "The person's location id",
}

_REF = re.compile(r"\{\s*([^{}]+?)\s*\}")
_PREFIX = "v__"
_FUNCS = {"min", "max", "round", "floor", "ceil", "abs", "_if_"}
_BINOPS = (ast.Add, ast.Sub, ast.Mult, ast.Div, ast.Mod, ast.Pow)
_CMPOPS = (ast.Eq, ast.NotEq, ast.Lt, ast.LtE, ast.Gt, ast.GtE)
MAX_LENGTH = 2000


class ExpressionError(ValueError):
    """The expression cannot be parsed, names something unknown, or cannot be worked out."""


def slug(name: str) -> str:
    """The reference name of a pay item or formula: "House Rent" -> "house_rent"."""
    return re.sub(r"_+", "_", re.sub(r"[^a-z0-9]", "_", (name or "").strip().lower())).strip("_")


class Expression:
    """A parsed expression. `refs` are the reference names it uses, in slug form."""

    def __init__(self, text: str):
        if text is None or not str(text).strip():
            raise ExpressionError("The expression is empty.")
        text = str(text)
        if len(text) > MAX_LENGTH:
            raise ExpressionError(f"The expression is longer than {MAX_LENGTH} characters.")
        self.text = text
        refs: list[str] = []

        def swap(m: re.Match) -> str:
            name = slug(m.group(1))
            if not name:
                raise ExpressionError(f"{m.group(0)} is not a valid reference.")
            refs.append(name)
            return f" {_PREFIX}{name} "

        python = _REF.sub(swap, text).replace("&&", " and ").replace("||", " or ")
        # if(cond, a, b) is the builder's function form; `if` is a Python keyword, so it is renamed.
        python = re.sub(r"(?<![\w.])if\s*\(", "_if_(", python)
        if "{" in python or "}" in python:
            raise ExpressionError("Braces do not match.")
        try:
            self.tree = ast.parse(python.strip(), mode="eval")
        except SyntaxError as exc:
            raise ExpressionError(f"The expression is not valid near position {exc.offset or 0}.") from None
        _check(self.tree.body)
        self.refs = tuple(dict.fromkeys(refs))

    def evaluate(self, resolve: Callable[[str], Decimal]) -> Decimal:
        """Work the expression out; `resolve` gives the value of a reference."""
        try:
            value = _eval(self.tree.body, resolve)
        except (DivisionByZero, ZeroDivisionError):
            raise ExpressionError("The expression divides by zero.") from None
        except InvalidOperation:
            raise ExpressionError("The expression does not work out to a number.") from None
        return _num(value)


def _check(node: ast.AST) -> None:
    if isinstance(node, ast.Constant):
        if isinstance(node.value, bool) or not isinstance(node.value, (int, float)):
            raise ExpressionError("Only numbers may be written in an expression.")
    elif isinstance(node, ast.Name):
        if not node.id.startswith(_PREFIX):
            raise ExpressionError(f"'{node.id}' is not known. Put references in braces, like {{gross_salary}}.")
    elif isinstance(node, ast.BinOp):
        if not isinstance(node.op, _BINOPS):
            raise ExpressionError("Only + - * / % and ** may be used.")
        _check(node.left)
        _check(node.right)
    elif isinstance(node, ast.UnaryOp):
        if not isinstance(node.op, (ast.USub, ast.UAdd, ast.Not)):
            raise ExpressionError("That operator is not allowed.")
        _check(node.operand)
    elif isinstance(node, ast.BoolOp):
        for v in node.values:
            _check(v)
    elif isinstance(node, ast.Compare):
        if not all(isinstance(op, _CMPOPS) for op in node.ops):
            raise ExpressionError("Only == != < <= > >= may be used to compare.")
        _check(node.left)
        for c in node.comparators:
            _check(c)
    elif isinstance(node, ast.IfExp):
        _check(node.test)
        _check(node.body)
        _check(node.orelse)
    elif isinstance(node, ast.Call):
        if not isinstance(node.func, ast.Name) or node.func.id not in _FUNCS or node.keywords:
            raise ExpressionError("Only these functions may be used: if, min, max, round, floor, ceil, abs.")
        counts = {"_if_": (3, 3), "round": (1, 2), "floor": (1, 1), "ceil": (1, 1), "abs": (1, 1),
                  "min": (1, 50), "max": (1, 50)}[node.func.id]
        if not counts[0] <= len(node.args) <= counts[1]:
            raise ExpressionError(f"{node.func.id.strip('_')}() takes {counts[0]} to {counts[1]} values.")
        for a in node.args:
            if isinstance(a, ast.Starred):
                raise ExpressionError("That is not allowed in an expression.")
            _check(a)
    else:
        raise ExpressionError("That is not allowed in an expression.")


def _num(value) -> Decimal:
    if isinstance(value, bool):
        return Decimal(1) if value else Decimal(0)
    if isinstance(value, Decimal):
        return value
    return Decimal(str(value))


def _eval(node: ast.AST, resolve):
    if isinstance(node, ast.Constant):
        return Decimal(str(node.value))
    if isinstance(node, ast.Name):
        return _num(resolve(node.id[len(_PREFIX):]))
    if isinstance(node, ast.BinOp):
        a, b = _num(_eval(node.left, resolve)), _num(_eval(node.right, resolve))
        if isinstance(node.op, ast.Add):
            return a + b
        if isinstance(node.op, ast.Sub):
            return a - b
        if isinstance(node.op, ast.Mult):
            return a * b
        if isinstance(node.op, ast.Div):
            return a / b
        if isinstance(node.op, ast.Mod):
            return a % b
        if abs(b) > 10:
            raise ExpressionError("Powers above 10 are not allowed.")
        return a ** b
    if isinstance(node, ast.UnaryOp):
        v = _eval(node.operand, resolve)
        if isinstance(node.op, ast.Not):
            return not _num(v)
        return -_num(v) if isinstance(node.op, ast.USub) else _num(v)
    if isinstance(node, ast.BoolOp):
        if isinstance(node.op, ast.And):
            result = True
            for v in node.values:
                result = _eval(v, resolve)
                if not _num(result):
                    return result
            return result
        result = False
        for v in node.values:
            result = _eval(v, resolve)
            if _num(result):
                return result
        return result
    if isinstance(node, ast.Compare):
        left = _num(_eval(node.left, resolve))
        for op, comp in zip(node.ops, node.comparators):
            right = _num(_eval(comp, resolve))
            ok = {ast.Eq: left == right, ast.NotEq: left != right, ast.Lt: left < right, ast.LtE: left <= right,
                  ast.Gt: left > right, ast.GtE: left >= right}[type(op)]
            if not ok:
                return False
            left = right
        return True
    if isinstance(node, ast.IfExp):
        return _eval(node.body, resolve) if _num(_eval(node.test, resolve)) else _eval(node.orelse, resolve)
    if isinstance(node, ast.Call):
        name = node.func.id
        if name == "_if_":
            test, yes, no = node.args
            return _eval(yes, resolve) if _num(_eval(test, resolve)) else _eval(no, resolve)
        args = [_num(_eval(a, resolve)) for a in node.args]
        if name == "min":
            return min(args)
        if name == "max":
            return max(args)
        if name == "abs":
            return abs(args[0])
        if name == "floor":
            return args[0].to_integral_value(rounding=ROUND_FLOOR)
        if name == "ceil":
            return args[0].to_integral_value(rounding=ROUND_CEILING)
        places = int(args[1]) if len(args) > 1 else 0
        return args[0].quantize(Decimal(1).scaleb(-places), rounding=ROUND_HALF_UP)
    raise ExpressionError("That is not allowed in an expression.")


class Resolver:
    """Resolves references for one person: system variables, pay item amounts already worked out, and
    formulas (worked out on demand, with loops refused)."""

    def __init__(self, variables: Mapping[str, Decimal], formulas: Mapping[str, Expression],
                 item_value: Callable[[str], Decimal | None]):
        self.variables = variables
        self.formulas = formulas
        self.item_value = item_value
        self._cache: dict[str, Decimal] = {}
        self._stack: list[str] = []

    def __call__(self, name: str) -> Decimal:
        if name in self.variables:
            return _num(self.variables[name])
        value = self.item_value(name)
        if value is not None:
            return value
        if name in self.formulas:
            if name in self._cache:
                return self._cache[name]
            if name in self._stack:
                raise ExpressionError(f"Formula {{{name}}} refers back to itself.")
            self._stack.append(name)
            try:
                value = self.formulas[name].evaluate(self)
            finally:
                self._stack.pop()
            self._cache[name] = value
            return value
        raise ExpressionError(f"{{{name}}} is not a variable, pay item or formula.")


def check_references(expr: Expression, known: set[str]) -> None:
    unknown = [r for r in expr.refs if r not in known]
    if unknown:
        raise ExpressionError(f"{{{unknown[0]}}} is not a variable, pay item or formula.")


def round_money(value: Decimal, mode: str = "actual") -> Decimal:
    """Rounding the settings offer: floor, ceil, round (nearest), actual / none (two decimals)."""
    if mode in ("floor",):
        return value.to_integral_value(rounding=ROUND_FLOOR).quantize(Decimal("0.01"))
    if mode in ("ceil",):
        return value.to_integral_value(rounding=ROUND_CEILING).quantize(Decimal("0.01"))
    if mode in ("round", "round_off"):
        return value.to_integral_value(rounding=ROUND_HALF_UP).quantize(Decimal("0.01"))
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
