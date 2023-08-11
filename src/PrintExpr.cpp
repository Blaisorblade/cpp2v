/*
 * Copyright (c) 2020-2023 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 */
#include "ClangPrinter.hpp"
#include "CoqPrinter.hpp"
#include "Formatter.hpp"
#include "Logging.hpp"
#include "OpaqueNames.hpp"
#include "clang/AST/Decl.h"
#include "clang/AST/Mangle.h"
#include "clang/AST/StmtVisitor.h"
#include "clang/AST/Type.h"
#include "clang/Basic/Builtins.h"
#include "clang/Basic/TargetInfo.h"
#include "clang/Basic/Version.inc"
#include <bit>

using namespace clang;
using namespace fmt;

#if CLANG_VERSION_MAJOR >= 15
void
printOptionalExpr(llvm::Optional<const Expr*> expr, CoqPrinter& print,
                  ClangPrinter& cprint, OpaqueNames& li) {
    if (expr.has_value()) {
        print.some();
        cprint.printExpr(expr.value(), print, li);
        print.end_ctor();
    } else {
        print.none();
    }
}
#else
void
printOptionalExpr(llvm::Optional<const Expr*> expr, CoqPrinter& print,
                  ClangPrinter& cprint, OpaqueNames& li) {
    if (expr.hasValue()) {
        print.some();
        cprint.printExpr(expr.getValue(), print, li);
        print.end_ctor();
    } else {
        print.none();
    }
}
#endif

bool
is_dependent(const Expr* expr) {
    return static_cast<bool>(expr->getDependence() &
                             ExprDependence::TypeValueInstantiation);
}

// todo(gmm): this is duplicated!
bool
is_builtin(const Decl* d) {
    if (const FunctionDecl* fd = dyn_cast_or_null<const FunctionDecl>(d)) {
        if (Builtin::ID::NotBuiltin != fd->getBuiltinID()) {
            return true;
        }
    }
    return false;
}

void
printCast(const CastExpr* ce, CoqPrinter& print, ClangPrinter& cprint) {
    switch (ce->getCastKind()) {
#define CASE(a, b)                                                             \
    case CastKind::CK_##a:                                                     \
        print.output() << #b;                                                  \
        break;

        CASE(LValueToRValue, Cl2r)
        CASE(Dependent, Cdependent)
        CASE(FunctionToPointerDecay, Cfun2ptr)
        CASE(NoOp, Cnoop)
        CASE(BitCast, Cbitcast)
        CASE(IntegralCast, Cintegral)
        CASE(IntegralToBoolean, Cint2bool)
        CASE(PointerToBoolean, Cptr2bool)
        CASE(PointerToIntegral, Cptr2int)
        CASE(IntegralToPointer, Cint2ptr)
        CASE(ArrayToPointerDecay, Carray2ptr)
        CASE(ConstructorConversion, Cctor)
        CASE(BuiltinFnToFnPtr, Cbuiltin2fun)
        CASE(NullToPointer, Cnull2ptr)
        CASE(ToVoid, C2void)
        CASE(FloatingToIntegral, Cfloat2int)
#undef CASE

    case CastKind::CK_DerivedToBase:
    case CastKind::CK_UncheckedDerivedToBase: {
        print.ctor("Cderived2base");
        // note that [path] does *not* include the type of the argument
        print.list(ce->path(), [&](auto print, auto i) {
            if (const Type* t = i->getType().getTypePtrOrNull()) {
                cprint.printTypeName(t->getAsRecordDecl(), print);
            } else {
                assert(false && "no type");
            }
        });
        print.end_ctor();
        break;
    }
    case CastKind::CK_BaseToDerived:
        print.ctor("Cbase2derived");
        // note that [path] does *not* include the type of the argument
        print.list(ce->path(), [&](auto print, auto i) {
            if (const Type* t = i->getType().getTypePtrOrNull()) {
                cprint.printTypeName(t->getAsRecordDecl(), print);
            } else {
                assert(false && "no type");
            }
        });
        print.end_ctor();
        break;
    default:
        logging::unsupported()
            << "unsupported cast kind \"" << ce->getCastKindName() << "\""
            << " (at " << cprint.sourceRange(ce->getSourceRange()) << ")\n";
        print.output() << "Cunsupported";
    }
}

class PrintExpr :
    public ConstStmtVisitor<PrintExpr, void, CoqPrinter&, ClangPrinter&,
                            const ASTContext&, OpaqueNames&> {
private:
    enum Done : unsigned {
        NONE = 0,
        V = 1,
        T = 2,
        O = 4,
        VT = V | T,
    };

    void done(const Expr* expr, CoqPrinter& print, ClangPrinter& cprint,
              Done want = Done::T) {
        if (want & Done::V) {
            print.output() << fmt::nbsp;
            cprint.printValCat(expr, print);
        }
        if (want & Done::T) {
            print.output() << fmt::nbsp;
            cprint.printQualType(expr->getType(), print);
        }
        if (want & Done::O) {
            print.output() << fmt::nbsp;
            cprint.printQualTypeOption(expr->getType(), print);
        }
        print.end_ctor();
    }

    void printVarRef(const ValueDecl* decl, CoqPrinter& print,
                     ClangPrinter& cprint, OpaqueNames& on) {
        auto check_static_local = [](const ValueDecl* decl) {
            auto t = dyn_cast<VarDecl>(decl);
            return t && t->isStaticLocal();
        };
        auto t = on.find_anon(decl);
        if (t != -1) {
            print.ctor("Lname", false) << "\"$" << t << "\"";
            print.end_ctor();
        } else if (decl->getDeclContext()->isFunctionOrMethod() and
                   not(isa<FunctionDecl>(decl) or check_static_local(decl))) {
            print.ctor("Lname", false);
            if (auto pd = dyn_cast<ParmVarDecl>(decl)) {
                cprint.printParamName(pd, print);
            } else {
                print.output() << "\"";
                decl->printName(print.output().nobreak());
                print.output() << "\"";
            }
            print.end_ctor();
        } else {
            print.ctor("Gname", false);
            cprint.printObjName(decl, print);
            print.end_ctor();
        }
    }

public:
    static PrintExpr printer;

    void VisitStmt(const Stmt* stmt, CoqPrinter& print, ClangPrinter& cprint,
                   const ASTContext&, OpaqueNames&) {
        logging::fatal() << "Error: while printing an expr, got a statement '"
                         << stmt->getStmtClassName() << " at "
                         << cprint.sourceRange(stmt->getSourceRange()) << "'\n";
        logging::die();
    }

    void unsupported_expr(const Expr* expr, CoqPrinter& print,
                          ClangPrinter& cprint) {
        using namespace logging;
        unsupported() << cprint.sourceLocation(expr->getBeginLoc())
                      << ": warning: unsupported expression ("
                      << expr->getStmtClassName() << ")\n";
#if CLANG_VERSION_MAJOR >= 11
        expr->dump(debug(), cprint.getContext());
#else
        expr->dump(debug());
#endif

        print.ctor("Eunsupported");
        print.str(expr->getStmtClassName());
        done(expr, print, cprint, Done::VT);
    }

    void VisitExpr(const Expr* expr, CoqPrinter& print, ClangPrinter& cprint,
                   const ASTContext& ctxt, OpaqueNames&) {
        unsupported_expr(expr, print, cprint);
    }

#if CLANG_VERSION_MAJOR >= 11
    void VisitRecoveryExpr(const RecoveryExpr* expr, CoqPrinter& print,
                           ClangPrinter& cprint, const ASTContext&,
                           OpaqueNames&) {
        using namespace logging;
        unsupported() << "Error detected when typechecking C++ code at "
                      << cprint.sourceRange(expr->getSourceRange()) << "\n"
                      << "Try fixing earlier errors\n";
        print.ctor("Eunsupported");
        print.str(expr->getStmtClassName());
        done(expr, print, cprint, Done::VT);
    }
#endif

    void printBinaryOperator(const BinaryOperator* expr, CoqPrinter& print,
                             ClangPrinter& cprint, const ASTContext& ctxt) {
        switch (expr->getOpcode()) {
#define CASE(k, s)                                                             \
    case BinaryOperatorKind::BO_##k:                                           \
        print.output() << s;                                                   \
        break;
            CASE(Add, "Badd")
            CASE(And, "Band")
            CASE(Cmp, "Bcmp")
            CASE(Div, "Bdiv")
            CASE(EQ, "Beq")
            CASE(GE, "Bge")
            CASE(GT, "Bgt")
            CASE(LE, "Ble")
            CASE(LT, "Blt")
            CASE(Mul, "Bmul")
            CASE(NE, "Bneq")
            CASE(Or, "Bor")
            CASE(Rem, "Bmod")
            CASE(Shl, "Bshl")
            CASE(Shr, "Bshr")
            CASE(Sub, "Bsub")
            CASE(Xor, "Bxor")
            CASE(PtrMemD, "Bdotp")
            CASE(PtrMemI, "Bdotip")
#undef CASE
        default:
            logging::unsupported()
                << "defaulting binary operator"
                << " (at " << cprint.sourceRange(expr->getSourceRange())
                << ")\n";
            print.ctor("Bunsupported")
                << "\"" << expr->getOpcodeStr() << "\"" << fmt::rparen;
            break;
        }
    }

    void VisitBinaryOperator(const BinaryOperator* expr, CoqPrinter& print,
                             ClangPrinter& cprint, const ASTContext& ctxt,
                             OpaqueNames& li) {
#define ACASE(k, v)                                                            \
    case BinaryOperatorKind::BO_##k##Assign:                                   \
        print.ctor("Eassign_op") << #v << fmt::nbsp;                           \
        break;

        switch (expr->getOpcode()) {
        case BinaryOperatorKind::BO_Comma:
            print.ctor("Ecomma");
            cprint.printExpr(expr->getLHS(), print);
            print.output() << fmt::nbsp;
            cprint.printExpr(expr->getRHS(), print);
            // TODO: Can be overloaded
            assert(expr->getRHS()->getType() == expr->getType() &&
                   "types must match");
            print.end_ctor(); // no type information
            return;
        case BinaryOperatorKind::BO_LAnd:
            print.ctor("Eseqand");
            cprint.printExpr(expr->getLHS(), print);
            print.output() << fmt::nbsp;
            cprint.printExpr(expr->getRHS(), print);
            // TODO: Can be overloaded
            assert(expr->getType().getTypePtr()->isBooleanType() &&
                   "&& is a bool");
            print.end_ctor(); // no type information
            return;
        case BinaryOperatorKind::BO_LOr:
            print.ctor("Eseqor");
            cprint.printExpr(expr->getLHS(), print);
            print.output() << fmt::nbsp;
            cprint.printExpr(expr->getRHS(), print);
            // TODO: Can be overloaded
            assert(expr->getType().getTypePtr()->isBooleanType() &&
                   "|| is a bool");
            print.end_ctor(); // no type information
            return;
        case BinaryOperatorKind::BO_Assign:
            print.ctor("Eassign");
            break;
            ACASE(Add, Badd)
            ACASE(And, Band)
            ACASE(Div, Bdiv)
            ACASE(Mul, Bmul)
            ACASE(Or, Bor)
            ACASE(Rem, Bmod)
            ACASE(Shl, Bshl)
            ACASE(Shr, Bshr)
            ACASE(Sub, Bsub)
            ACASE(Xor, Bxor)
        default:
            print.ctor("Ebinop");
            printBinaryOperator(expr, print, cprint, ctxt);
            print.output() << fmt::nbsp;
            break;
        }
#undef ACASE
        cprint.printExpr(expr->getLHS(), print, li);
        print.output() << fmt::nbsp;
        cprint.printExpr(expr->getRHS(), print, li);
        done(expr, print, cprint, print.templates() ? Done::O : Done::T);
    }

    void VisitDependentScopeDeclRefExpr(const DependentScopeDeclRefExpr* expr,
                                        CoqPrinter& print, ClangPrinter& cprint,
                                        const ASTContext& ctxt,
                                        OpaqueNames& li) {
        ConstStmtVisitor<
            PrintExpr, void, CoqPrinter&, ClangPrinter&, const ASTContext&,
            OpaqueNames&>::VisitDependentScopeDeclRefExpr(expr, print, cprint,
                                                          ctxt, li);
    }

    void printUnaryOperator(const UnaryOperator* expr, CoqPrinter& print,
                            ClangPrinter& cprint) {
        switch (expr->getOpcode()) {
#define CASE(k, s)                                                             \
    case UnaryOperatorKind::UO_##k:                                            \
        print.output() << s;                                                   \
        break;
            CASE(Plus, "Uplus")
            CASE(Minus, "Uminus")
            CASE(Not, "Ubnot")
            CASE(LNot, "Unot")
            CASE(PostDec, "<PostDec>")
            CASE(PostInc, "<PostInc>")
            CASE(PreDec, "<PreDec>")
            CASE(PreInc, "<PreInc>")
#undef CASE
        default:
            logging::unsupported()
                << "Error: unsupported unary operator"
                << " (at " << cprint.sourceRange(expr->getSourceRange())
                << ")\n";
            print.output() << "(Uunsupported \""
                           << UnaryOperator::getOpcodeStr(expr->getOpcode())
                           << "\")";
            break;
        }
    }

    void VisitUnaryOperator(const UnaryOperator* expr, CoqPrinter& print,
                            ClangPrinter& cprint, const ASTContext&,
                            OpaqueNames& li) {
        switch (expr->getOpcode()) {
        case UnaryOperatorKind::UO_AddrOf:
            print.ctor("Eaddrof");
            cprint.printExpr(expr->getSubExpr(), print, li);
            print.end_ctor(); // elide type
            return;
        case UnaryOperatorKind::UO_Deref:
            print.ctor("Ederef");
            break;
        case UnaryOperatorKind::UO_PostInc:
            print.ctor("Epostinc");
            break;
        case UnaryOperatorKind::UO_PreInc:
            print.ctor("Epreinc");
            break;
        case UnaryOperatorKind::UO_PostDec:
            print.ctor("Epostdec");
            break;
        case UnaryOperatorKind::UO_PreDec:
            print.ctor("Epredec");
            break;
        default:
            print.ctor("Eunop");
            printUnaryOperator(expr, print, cprint);
            print.output() << fmt::nbsp;
        }
        cprint.printExpr(expr->getSubExpr(), print, li);
        done(expr, print, cprint, print.templates() ? Done::O : Done::T);
    }

    void VisitDeclRefExpr(const DeclRefExpr* expr, CoqPrinter& print,
                          ClangPrinter& cprint, const ASTContext& ctxt,
                          OpaqueNames& on) {
        auto d = expr->getDecl();
        if (auto ecd = dyn_cast<EnumConstantDecl>(d)) {
            // References to `enum` constants are special because
            // they can be referenced both at the enumeration type
            // and (within the `enum` declaration) they can be
            // referenced at the underlying type. Here, we
            // unify these two so that the type of a reference to
            // an `enum` constant is *always* the `enum` type.
            // To match the type of the expression, we insert
            // an implicit integral cast.
            if (expr->getType()->isEnumeralType()) {
                // nothing special to do.
                print.ctor("Econst_ref", false);
                print.ctor("Gname", false);
                cprint.printObjName(d, print);
                print.end_ctor();
                done(expr, print, cprint);
            } else {
                // TODO: is is possible to determine the `DeclContext` that
                // this expression occurs in? If so, then we could assert that
                // this is in the scope of the enumeration.
                print.ctor("Eenum_const_at", false);
                cprint.printObjName(d, print);
                print.output() << fmt::nbsp;
                cprint.printQualType(ecd->getType(), print);
                done(expr, print, cprint);
            }
        } else {
            // We add `Eread_ref` nodes when the type of the
            // variable is a reference.
            if (d->getType()->isReferenceType()) {
                print.ctor("Eread_ref");
            }

            print.ctor("Evar", false);
            printVarRef(d, print, cprint, on);
            done(expr, print, cprint);

            if (d->getType()->isReferenceType()) {
                print.end_ctor();
            }
        }
    }

    void VisitUnresolvedLookupExpr(const UnresolvedLookupExpr* expr,
                                   CoqPrinter& print, ClangPrinter& cprint,
                                   const ASTContext&, OpaqueNames&) {
        if (!print.templates())
            return unsupported_expr(expr, print, cprint);

        auto name = expr->getName();
        switch (name.getNameKind()) {
        case DeclarationName::NameKind::Identifier:
            /*
            Example: A function name that couldn't be resolved due to an
            argument depending on a template parameter.
            */

            print.str(name.getAsString());
            break;

        default:
            return unsupported_expr(expr, print, cprint);
        }
    }

    void VisitCallExpr(const CallExpr* expr, CoqPrinter& print,
                       ClangPrinter& cprint, const ASTContext&,
                       OpaqueNames& li) {
        if (print.templates() && is_dependent(expr)) {
            /*
            Either the function or an argument is dependent.
            */
            print.ctor("Eunresolved_call");
            cprint.printExpr(expr->getCallee(), print, li);
            print.output() << fmt::line;
            print.list(expr->arguments(), [&](auto print, auto i) {
                cprint.printExpr(i, print, li);
            });
            print.end_ctor();
            return;
        }

        print.ctor("Ecall");
        cprint.printExpr(expr->getCallee(), print, li);
        print.output() << fmt::line;
        print.list(expr->arguments(),
                   [&](auto print, auto i) { cprint.printExpr(i, print, li); });
        done(expr, print, cprint, print.templates() ? Done::NONE : Done::T);
    }

    auto&& printOverloadableOperator(OverloadedOperatorKind oo,
                                     CoqPrinter& print) {
        switch (oo) {
#define OVERLOADED_OPERATOR(Name, Spelling, Token, Unary, Binary, MemberOnly)  \
    case OO_##Name:                                                            \
        return print.output() << "OO" << #Name;
#include "clang/Basic/OperatorKinds.def"
#undef OVERLOADED_OPERATOR
        }
    }

    void VisitCXXOperatorCallExpr(const CXXOperatorCallExpr* expr,
                                  CoqPrinter& print, ClangPrinter& cprint,
                                  const ASTContext& ctxt, OpaqueNames& li) {
        // TODO operator calls sometimes have stricter order of evaluation
        // than regular function calls. Because our semantics overapproximates
        // the possible behaviors, it is sound for us to directly desugar them.
        auto callee = expr->getCalleeDecl();
        // some operator calls are actually method calls.
        // because we (and C++) distinguish between member calls
        // and function calls, we need to desugar this to a method
        // if the called function is a method.
        if (auto method = dyn_cast<CXXMethodDecl>(callee)) {
            assert(!method->isStatic() &&
                   "operator overloads can not be static");
            print.ctor("Eoperator_member_call");
            printOverloadableOperator(expr->getOperator(), print) << fmt::nbsp;

            cprint.printObjName(method, print);
            print.output() << fmt::nbsp
                           << (method->isVirtual() ? "Virtual" : "Direct")
                           << fmt::nbsp;
            cprint.printQualType(method->getType(), print);
            print.output() << fmt::nbsp;

            cprint.printExpr(expr->getArg(0), print, li);

            print.output() << fmt::nbsp;
            // note skip the first parameter because it is the object.
            print.list_range(
                expr->arg_begin() + 1, expr->arg_end(),
                [&](auto print, auto i) { cprint.printExpr(i, print, li); });

        } else if (auto function = dyn_cast<FunctionDecl>(callee)) {
            print.ctor("Eoperator_call");
            printOverloadableOperator(expr->getOperator(), print) << fmt::nbsp;

            cprint.printObjName(function, print);
            print.output() << fmt::nbsp;
            cprint.printQualType(function->getType(), print);
            print.output() << fmt::nbsp;
            print.list(expr->arguments(), [&](auto print, auto i) {
                cprint.printExpr(i, print, li);
            });
        } else {
            logging::unsupported() << "unsupported operator call";
            logging::die();
        }

        done(expr, print, cprint);
    }

    void VisitCastExpr(const CastExpr* expr, CoqPrinter& print,
                       ClangPrinter& cprint, const ASTContext&,
                       OpaqueNames& li) {
        if (expr->getCastKind() == CastKind::CK_ConstructorConversion ||
            expr->getCastKind() == CastKind::CK_UserDefinedConversion) {
            auto cf = expr->getConversionFunction();
            assert(cf &&
                   "UserDefinedConversion must have a ConversionFunction");
            // desugar user casts to function calls
            auto vd = dyn_cast<ValueDecl>(cf);
            assert(vd && "conversion function must be a [ValueDecl]");
            print.ctor("Ecast");
            print.ctor("Cuser");
            cprint.printObjName(vd, print);
            print.end_ctor();

            print.output() << fmt::nbsp;
            cprint.printExpr(expr->getSubExpr(), print, li);
            done(expr, print, cprint, Done::VT);
        } else {
            print.ctor("Ecast");
            printCast(expr, print, cprint);

            print.output() << fmt::nbsp;
            cprint.printExpr(expr->getSubExpr(), print, li);
            done(expr, print, cprint, Done::VT);
        }
    }

    void VisitImplicitCastExpr(const ImplicitCastExpr* expr, CoqPrinter& print,
                               ClangPrinter& cprint, const ASTContext& ctxt,
                               OpaqueNames& li) {
        // todo(gmm): this is a complete hack because there is no way that i know of
        // to get the type of a builtin. what this does is get the type of the expression
        // that contains the builtin.
        if (expr->getCastKind() == CastKind::CK_BuiltinFnToFnPtr) {
            auto ref = dyn_cast<DeclRefExpr>(expr->getSubExpr());
            assert(ref && "builtin function to function pointer must be applied to a literal variable");
            assert(is_builtin(ref->getDecl()));
            print.ctor("Ebuiltin", false);
            // assume that this is a builtin
            cprint.printObjName(ref->getDecl(), print);
            print.output() << fmt::nbsp;
            auto type = expr->getType();
            assert(type->isPointerType() && "builtin to pointer is not a pointer");
            cprint.printQualType(type.getTypePtr()->getPointeeType(), print);
            print.end_ctor();
            return;
        }
        VisitCastExpr(expr, print, cprint, ctxt, li);
    }

    void VisitCXXNamedCastExpr(const CXXNamedCastExpr* expr, CoqPrinter& print,
                               ClangPrinter& cprint, const ASTContext& ctxt,
                               OpaqueNames& li) {
        print.ctor("Ecast");
        if (isa<CXXReinterpretCastExpr>(expr)) {
            print.ctor("Creinterpret", false);
            cprint.printQualType(expr->getType(), print);
            print.end_ctor();
        } else if (isa<CXXConstCastExpr>(expr)) {
            print.ctor("Cconst", false);
            cprint.printQualType(expr->getType(), print);
            print.end_ctor();
        } else if (isa<CXXStaticCastExpr>(expr)) {
            print.ctor("Cstatic", false);
            printCast(expr, print, cprint);
            print.end_ctor();
        } else if (isa<CXXDynamicCastExpr>(expr)) {
            print.ctor("Cdynamic", false);
            cprint.printQualType(expr->getSubExpr()->getType(), print);
            print.output() << fmt::nbsp;
            cprint.printQualType(expr->getType(), print);
            print.end_ctor();
        } else {
            using namespace logging;
            fatal() << "Error: unknown named cast" << expr->getCastKindName()
                    << " (at "
                    << expr->getSourceRange().printToString(
                           ctxt.getSourceManager())
                    << ")\n";
            die();
        }
        print.output() << fmt::nbsp;
        cprint.printExpr(expr->getSubExpr(), print, li);
        done(expr, print, cprint, Done::VT);
    }

    void VisitIntegerLiteral(const IntegerLiteral* lit, CoqPrinter& print,
                             ClangPrinter& cprint, const ASTContext&,
                             OpaqueNames&) {
        print.ctor("Eint", false);
        SmallString<32> s;
        if (lit->getType()->isSignedIntegerOrEnumerationType()) {
            lit->getValue().toStringSigned(s);
        } else {
            lit->getValue().toStringUnsigned(s);
        }
        print.output() << s << "%Z";
        done(lit, print, cprint);
    }

    void VisitCharacterLiteral(const CharacterLiteral* lit, CoqPrinter& print,
                               ClangPrinter& cprint, const ASTContext&,
                               OpaqueNames&) {
        print.ctor("Echar", false) << lit->getValue() << "%N";
        done(lit, print, cprint);
    }

    static void print_string_type(const Expr* expr, CoqPrinter& print,
                                  ClangPrinter& cprint) {
        if (auto at = dyn_cast<ArrayType>(expr->getType().getTypePtr())) {
            print.output() << fmt::nbsp;
            cprint.printType(at->getElementType().getTypePtr(), print);
        } else {
            assert(false && "string literal does not have array type");
        }
    }

    void VisitStringLiteral(const StringLiteral* lit, CoqPrinter& print,
                            ClangPrinter& cprint, const ASTContext& ctxt,
                            OpaqueNames&) {
        print.ctor("Estring", false);
        // We get the string literal in bytes, but we need to encode it
        // as unsigned characters (not necessarily `char`) using the
        // internal character representation of BRiCk.
        auto bytes = lit->getBytes();
        const unsigned width = lit->getCharByteWidth();
        print.begin_list();
        for (unsigned i = 0, len = lit->getByteLength(); i < len;) {
            unsigned long long byte = 0;
            // TODO confirm that this is correct
            if (llvm::support::endian::system_endianness() ==
                llvm::support::endianness::big) {
                for (unsigned j = 0; j < width; ++j) {
                    byte = (byte << 8) | static_cast<unsigned char>(bytes[i++]);
                }
            } else {
                for (unsigned j = 0; j < width; ++j) {
                    byte = (byte << 8) |
                           static_cast<unsigned char>(bytes[i + width - j - 1]);
                }
                i += width;
            }
            print.output() << byte << "%N";
            print.cons();
        }
        print.end_list();
        // NOTE: the trailing `\0` is added by the semantics
        print_string_type(lit, print, cprint);
        print.end_ctor();
    }

    void VisitPredefinedExpr(const PredefinedExpr* expr, CoqPrinter& print,
                             ClangPrinter& cprint, const ASTContext&,
                             OpaqueNames&) {
        // [PredefinedExpr] constructs a [string] which is always ascii
        print.ctor("Estring");
        print.ctor("BS.string_to_bytes");
        print.str(expr->getFunctionName()->getString());
        print.end_ctor();
        print_string_type(expr, print, cprint);
        print.end_ctor();
    }

    void VisitCXXBoolLiteralExpr(const CXXBoolLiteralExpr* lit,
                                 CoqPrinter& print, ClangPrinter& cprint,
                                 const ASTContext&, OpaqueNames&) {
        if (lit->getValue()) {
            print.output() << "(Ebool true)";
        } else {
            print.output() << "(Ebool false)";
        }
    }

    void VisitFloatingLiteral(const FloatingLiteral* lit, CoqPrinter& print,
                              ClangPrinter& cprint, const ASTContext&,
                              OpaqueNames&) {
        print.ctor("Eunsupported") << fmt::nbsp << "float: \"";
        lit->getValue().print(print.output().nobreak());
        print.output() << "\"";
        done(lit, print, cprint, Done::VT);
    }

    void VisitMemberExpr(const MemberExpr* expr, CoqPrinter& print,
                         ClangPrinter& cprint, const ASTContext&,
                         OpaqueNames& li) {
        /* TCB: semantics of accesses to static members.
        When `m` is a static member of `T` and `e : T`,
        we desugar `e->member` to `e, T::member`.
        */
        if (auto vd = dyn_cast<VarDecl>(expr->getMemberDecl())) {
            if (vd->isStaticDataMember()) {
                print.ctor("Ecomma");
                cprint.printExpr(expr->getBase(), print, li);
                print.output() << fmt::nbsp;
                auto is_ref = vd->getType()->isReferenceType();
                if (is_ref)
                    print.ctor("Eread_ref");
                print.ctor("Evar", false);
                printVarRef(vd, print, cprint, li);
                print.output() << fmt::nbsp;
                done(expr, print, cprint);
                if (is_ref)
                    print.end_ctor();
                print.end_ctor();
                return;
            }
        } else if (auto md = dyn_cast<CXXMethodDecl>(expr->getMemberDecl())) {
            if (md->isStatic()) {
                print.ctor("Ecomma");
                cprint.printExpr(expr->getBase(), print, li);
                print.output() << fmt::nbsp;
                print.ctor("Evar", false);
                printVarRef(md, print, cprint, li);
                print.output() << fmt::nbsp;
                cprint.printQualType(md->getType(), print);
                print.end_ctor();
                print.end_ctor();
                return;
            }
        }

        auto is_ref = expr->getMemberDecl()->getType()->isReferenceType();
        if (is_ref)
            print.ctor("Eread_ref");
        print.ctor("Emember");

        auto base = expr->getBase();
        __attribute__((unused)) auto record_type =
            expr->getMemberDecl()->getDeclContext();
        // TODO Assert that the type of the base is the type of the field.
        if (expr->isArrow()) {
            print.ctor("Ederef");
            cprint.printExpr(base, print, li);
            print.output() << fmt::nbsp;
            cprint.printQualType(base->getType()->getPointeeType(), print);
            assert(base->getType()->getPointeeCXXRecordDecl() == record_type &&
                   "record projection type mismatch");
            print.end_ctor();
        } else {
            cprint.printExpr(base, print, li);
            assert(base->getType()->getAsCXXRecordDecl() == record_type &&
                   "record projection type mismatch");
        }

        print.output() << fmt::nbsp;
        //print.str(expr->getMemberDecl()->getNameAsString());
        cprint.printField(expr->getMemberDecl(), print);
        done(expr, print, cprint);
        if (is_ref)
            print.end_ctor();
    }

    void VisitArraySubscriptExpr(const ArraySubscriptExpr* expr,
                                 CoqPrinter& print, ClangPrinter& cprint,
                                 const ASTContext&, OpaqueNames& li) {
        print.ctor("Esubscript");
        cprint.printExpr(expr->getLHS(), print, li);
        print.output() << fmt::nbsp;
        cprint.printExpr(expr->getRHS(), print, li);
        done(expr, print, cprint, print.templates() ? Done::O : Done::T);
    }

    void VisitCXXConstructExpr(const CXXConstructExpr* expr, CoqPrinter& print,
                               ClangPrinter& cprint, const ASTContext&,
                               OpaqueNames& li) {
        print.ctor("Econstructor");
        // print.output() << expr->isElidable() << fmt::nbsp;
        cprint.printObjName(expr->getConstructor(), print);
        print.output() << fmt::nbsp;
        print.list(expr->arguments(),
                   [&](auto print, auto i) { cprint.printExpr(i, print, li); });
        //print.output() << fmt::nbsp << expr->isElidable();
        done(expr, print, cprint);
    }

    void VisitCXXInheritedCtorInitExpr(const CXXInheritedCtorInitExpr* expr,
                                       CoqPrinter& print, ClangPrinter& cprint,
                                       const ASTContext&, OpaqueNames& li) {
        print.ctor("Econstructor");
        // print.output() << expr->isElidable() << fmt::nbsp;
        auto ctor = expr->getConstructor();
        cprint.printObjName(ctor, print);
        print.output() << fmt::nbsp;
        // NOTE clang does not include the arguments to the constructor here
        // they are forwarded from the function itself; however, with the
        // data that we have, we can't get to the actual function.
        // A good solution would be to store this information in the [OpaqueNames]
        // object, but for now, we can get away with printing the variable references
        // directly.
        auto idx = 0;
        print.list(ctor->parameters(), [&](auto print, auto i) {
            print.ctor("Evar", false);
            print.ctor("Lname", false);
            print.output() << "\"#" << idx << "\"";
            print.end_ctor();
            print.output() << fmt::nbsp;
            cprint.printQualType(i->getType(), print);
            print.end_ctor();
            ++idx;
        });
        //print.output() << fmt::nbsp << expr->isElidable();
        done(expr, print, cprint);
    }

    void VisitCXXMemberCallExpr(const CXXMemberCallExpr* expr,
                                CoqPrinter& print, ClangPrinter& cprint,
                                const ASTContext&, OpaqueNames& li) {
        print.ctor("Emember_call");
        auto callee = expr->getCallee()->IgnoreParens();
        auto method = expr->getMethodDecl();
        if (auto me = dyn_cast<MemberExpr>(callee)) {
            print.ctor("inl") << fmt::lparen;
            cprint.printObjName(method, print);
            print.output() << "," << fmt::nbsp;
            if (me->hasQualifier() or not method->isVirtual()) {
                // not virtual call
                print.output() << "Direct";
            } else {
                print.output() << "Virtual";
            }
            print.output() << "," << fmt::nbsp;

            if (const CXXMethodDecl* const md =
                    dyn_cast<CXXMethodDecl>(me->getMemberDecl())) {
                cprint.printQualType(md->getType(), print);
            } else {
                assert(false &&
                       "MemberDecl in MemberCall must be a MethodDecl");
            }
            print.output() << fmt::rparen;
            print.end_ctor();

            print.output() << fmt::nbsp;
            if (me->isArrow()) {
                // NOTE: the C++ standard states that a `*` is always an `lvalue`.
                print.ctor("Ederef");
                cprint.printExpr(expr->getImplicitObjectArgument(), print, li);
                print.output() << fmt::nbsp;
                cprint.printQualType(expr->getImplicitObjectArgument()
                                         ->getType()
                                         ->getPointeeType(),
                                     print);
                print.end_ctor();
            } else {
                cprint.printExpr(expr->getImplicitObjectArgument(), print, li);
            }
        } else if (auto bo = dyn_cast<BinaryOperator>(callee)) {
            assert(bo != nullptr && "expecting a binary operator");
            logging::unsupported()
                << "member pointers are currently not "
                   "supported in the logic."
                << " (at " << cprint.sourceRange(bo->getSourceRange()) << ")\n";
            print.ctor("inr");
            cprint.printExpr(bo->getRHS(), print, li);
            print.end_ctor() << fmt::nbsp;

            switch (bo->getOpcode()) {
            case BinaryOperatorKind::BO_PtrMemI:
                print.output() << "Lvalue";
                print.ctor("Ederef");
                cprint.printExpr(expr->getImplicitObjectArgument(), print, li);
                print.output() << fmt::nbsp;
                cprint.printQualType(expr->getImplicitObjectArgument()
                                         ->getType()
                                         ->getPointeeType(),
                                     print);
                print.end_ctor();
                break;
            case BinaryOperatorKind::BO_PtrMemD:
                cprint.printExpr(expr->getImplicitObjectArgument(), print, li);
                break;
            default:
                assert(false &&
                       "pointer to member function should be a pointer");
            }
        } else {
            assert(false && "no method and not a binary operator");
        }
        print.output() << fmt::nbsp;
        print.list(expr->arguments(),
                   [&](auto print, auto i) { cprint.printExpr(i, print, li); });
#if 0
        print.output() << fmt::nbsp << fmt::lparen;
        for (auto i : expr->arguments()) {
            cprint.printExpr(i, print, li);
            print.cons();
        }
        print.end_list();
#endif
        done(expr, print, cprint, print.templates() ? Done::NONE : Done::T);
    }

    void VisitCXXDefaultArgExpr(const CXXDefaultArgExpr* expr,
                                CoqPrinter& print, ClangPrinter& cprint,
                                const ASTContext&, OpaqueNames& li) {
        print.ctor("Eimplicit");
        cprint.printExpr(expr->getExpr(), print, li);
        print.end_ctor();
    }

    void VisitConditionalOperator(const ConditionalOperator* expr,
                                  CoqPrinter& print, ClangPrinter& cprint,
                                  const ASTContext&, OpaqueNames& li) {
        print.ctor("Eif");
        cprint.printExpr(expr->getCond(), print, li);
        print.output() << fmt::nbsp;
        cprint.printExpr(expr->getTrueExpr(), print, li);
        print.output() << fmt::nbsp;
        cprint.printExpr(expr->getFalseExpr(), print, li);
        done(expr, print, cprint, Done::VT);
    }

    void VisitBinaryConditionalOperator(const BinaryConditionalOperator* expr,
                                        CoqPrinter& print, ClangPrinter& cprint,
                                        const ASTContext&, OpaqueNames& li) {
        print.ctor("Eif2");
        auto index = li.fresh(expr->getOpaqueValue());
        print.output() << index << fmt::nbsp;
        cprint.printExpr(expr->getCommon(), print, li);
        li.inc_index_count();
        print.output() << fmt::nbsp;
        cprint.printExpr(expr->getCond(), print, li);
        print.output() << fmt::nbsp;
        cprint.printExpr(expr->getTrueExpr(), print, li);
        print.output() << fmt::nbsp;
        cprint.printExpr(expr->getFalseExpr(), print, li);
        li.dec_index_count();
        done(expr, print, cprint, Done::VT);
    }

#if CLANG_VERSION_MAJOR >= 8
    void VisitConstantExpr(const ConstantExpr* expr, CoqPrinter& print,
                           ClangPrinter& cprint, const ASTContext& ctxt,
                           OpaqueNames& li) {
        this->Visit(expr->getSubExpr(), print, cprint, ctxt, li);
    }
#endif

    void VisitParenExpr(const ParenExpr* e, CoqPrinter& print,
                        ClangPrinter& cprint, const ASTContext& ctxt,
                        OpaqueNames& li) {
        this->Visit(e->getSubExpr(), print, cprint, ctxt, li);
    }

    void VisitParenListExpr(const ParenListExpr* expr, CoqPrinter& print,
                            ClangPrinter& cprint, const ASTContext& ctxt,
                            OpaqueNames& names) {
        if (!print.templates())
            return unsupported_expr(expr, print, cprint);
        assert(is_dependent(expr));

        print.ctor("Eunresolved_parenlist");

        cprint.printQualTypeOption(expr->getType(), print);
        print.output() << fmt::nbsp;

        // `print.list` unavailable because there's no constant
        // version of `ParenListExpr::exprs`.
        // TODO: Define and use iterator over integer ranges.

        auto n = expr->getNumExprs();
        if (n == 0)
            print.output() << "nil";
        else {
            print.begin_list();
            for (unsigned i = 0; i < n; i++) {
                cprint.printExpr(expr->getExpr(i), print, names);
                print.cons();
            }
            print.end_list();
        }
        print.end_ctor();
    }

    void VisitInitListExpr(const InitListExpr* expr, CoqPrinter& print,
                           ClangPrinter& cprint, const ASTContext&,
                           OpaqueNames& li) {
        if (expr->isTransparent()) {
            // "transparent" intializer lists are no-ops in the semantics
            // and are retained in the clang AST only for printing purposes.
            assert(expr->inits().size() == 1);
            cprint.printExpr(expr->getInit(0), print, li);
        } else {
            print.ctor("Einitlist");

            print.list(expr->inits(), [&](auto print, auto i) {
                cprint.printExpr(i, print, li);
            }) << fmt::nbsp;

            if (expr->getArrayFiller()) {
                print.some();
                cprint.printExpr(expr->getArrayFiller(), print, li);
                print.end_ctor();
            } else {
                print.none();
            }

            done(expr, print, cprint);
        }
    }

    void VisitCXXThisExpr(const CXXThisExpr* expr, CoqPrinter& print,
                          ClangPrinter& cprint, const ASTContext&,
                          OpaqueNames&) {
        print.ctor("Ethis", false);
        done(expr, print, cprint);
    }

    void VisitCXXNullPtrLiteralExpr(const CXXNullPtrLiteralExpr* expr,
                                    CoqPrinter& print, ClangPrinter& cprint,
                                    const ASTContext&, OpaqueNames&) {
        print.output()
            << "Enull"; // note(gmm): null has a special "nullptr_t" type
    }

    void VisitUnaryExprOrTypeTraitExpr(const UnaryExprOrTypeTraitExpr* expr,
                                       CoqPrinter& print, ClangPrinter& cprint,
                                       const ASTContext& ctxt,
                                       OpaqueNames& li) {
        auto do_arg = [&print, &cprint, &li, expr]() {
            if (expr->isArgumentType()) {
                print.ctor("inl", false);
                cprint.printQualType(expr->getArgumentType(), print);
                print.output() << fmt::rparen;
            } else if (expr->getArgumentExpr()) {
                print.ctor("inr", false);
                cprint.printExpr(expr->getArgumentExpr(), print, li);
                print.output() << fmt::rparen;
            } else {
                assert(false);
                //fatal("argument to sizeof/alignof is not a type or an expression.");
            }
        };

        if (expr->getKind() == UnaryExprOrTypeTrait::UETT_AlignOf) {
            print.ctor("Ealign_of", false);
            do_arg();
            done(expr, print, cprint);
        } else if (expr->getKind() == UnaryExprOrTypeTrait::UETT_SizeOf) {
            print.ctor("Esize_of", false);
            do_arg();
            done(expr, print, cprint);
        } else {
            using namespace logging;
            fatal() << "Error: unsupported expression "
                       "`UnaryExprOrTypeTraitExpr` at "
                    << expr->getSourceRange().printToString(
                           ctxt.getSourceManager())
                    << "\n";
            die();
        }
    }

    void VisitOffsetOfExpr(const OffsetOfExpr* expr, CoqPrinter& print,
                           ClangPrinter& cprint, const ASTContext& ctxt,
                           OpaqueNames&) {
        print.ctor("Eoffset_of");
        assert(expr->getNumComponents() == 1);
        auto comm = expr->getComponent(0);
        switch (comm.getKind()) {
        case OffsetOfNode::Kind::Field:
            print.ctor("Oo_Field");
            cprint.printField(comm.getField(), print);
            print.end_ctor();
            break;

        default:
            using namespace logging;
            unsupported()
                << "offsetof() is only supported on fields and base classes: "
                << expr->getSourceRange().printToString(ctxt.getSourceManager())
                << "\n";
            die();
            break;
        }
        done(expr, print, cprint);
    }

    void
    VisitSubstNonTypeTemplateParmExpr(const SubstNonTypeTemplateParmExpr* expr,
                                      CoqPrinter& print, ClangPrinter& cprint,
                                      const ASTContext& ctxt, OpaqueNames& li) {
        this->Visit(expr->getReplacement(), print, cprint, ctxt, li);
    }

    void VisitCXXNewExpr(const CXXNewExpr* expr, CoqPrinter& print,
                         ClangPrinter& cprint, const ASTContext&,
                         OpaqueNames& li) {
        print.ctor("Enew");
        if (expr->getOperatorNew()) {
            print.begin_tuple();
            cprint.printObjName(expr->getOperatorNew(), print);
            print.next_tuple();
            cprint.printQualType(expr->getOperatorNew()->getType(), print);
            print.end_tuple() << fmt::nbsp;
        } else {
            logging::fatal() << "missing operator [new]\n";
            logging::die();
        }

        print.list(expr->placement_arguments(), [&](auto print, auto arg) {
            cprint.printExpr(arg, print, li);
        }) << fmt::nbsp;

        cprint.printQualType(expr->getAllocatedType(), print);

        print.output() << fmt::nbsp;

        printOptionalExpr(expr->getArraySize(), print, cprint, li);

        print.output() << fmt::nbsp;

        if (auto v = expr->getInitializer()) {
            print.some();
            cprint.printExpr(v, print, li);
            print.end_ctor();
        } else {
            print.none();
        }

        print.end_ctor();
    }

    void VisitCXXDeleteExpr(const CXXDeleteExpr* expr, CoqPrinter& print,
                            ClangPrinter& cprint, const ASTContext&,
                            OpaqueNames& li) {
        print.ctor("Edelete");
        print.output() << fmt::BOOL(expr->isArrayForm()) << fmt::nbsp;

        if (auto op = expr->getOperatorDelete()) {
            if (op->isDestroyingOperatorDelete()) {
                logging::fatal() << "destroying delete is not supported\n";
                logging::die();
            }
            print.begin_tuple();
            cprint.printObjName(op, print);
            print.next_tuple();
            cprint.printQualType(op->getType(), print);
            print.end_tuple();
        } else {
            logging::fatal() << "missing [delete] operator\n";
            logging::die();
        }
        print.output() << fmt::nbsp;

        cprint.printExpr(expr->getArgument(), print, li);

        print.output() << fmt::nbsp;

        cprint.printQualType(expr->getDestroyedType(), print);

        // no need to print the type information on [delete]
        print.end_ctor();
    }

    void VisitExprWithCleanups(const ExprWithCleanups* expr, CoqPrinter& print,
                               ClangPrinter& cprint, const ASTContext&,
                               OpaqueNames& li) {
        // NOTE candidate for removal
        // our semantics cleans everything, so we don't need to
        // mark this explicitly.
        print.ctor("Eandclean");
#ifdef DEBUG
        llvm::errs() << "and_clean objects: " << expr->getNumObjects() << "\n";
        for (const BlockDecl* i : expr->getObjects()) {
            llvm::errs() << static_cast<const void*>(i) << "\n";
        }
#endif /* DEBUG */
        cprint.printExpr(expr->getSubExpr(), print, li);
        print.end_ctor();
    }

    void VisitMaterializeTemporaryExpr(const MaterializeTemporaryExpr* expr,
                                       CoqPrinter& print, ClangPrinter& cprint,
                                       const ASTContext& ctxt,
                                       OpaqueNames& li) {
        if (expr->getExtendingDecl() != nullptr) {
            using namespace logging;
            fatal() << "Error: binding a reference to a temporary is not "
                       "(yet?) supported "
                       "(scope extrusion)"
                    << expr->getSourceRange().printToString(
                           ctxt.getSourceManager())
                    << "\n";
            die();
        }

        print.ctor("Ematerialize_temp");
#if CLANG_VERSION_MAJOR >= 10
        cprint.printExpr(expr->getSubExpr(), print, li);
#else
        cprint.printExpr(expr->GetTemporaryExpr(), print);
#endif
        done(expr, print, cprint, Done::V);
    }

    void VisitCXXBindTemporaryExpr(const CXXBindTemporaryExpr* expr,
                                   CoqPrinter& print, ClangPrinter& cprint,
                                   const ASTContext&, OpaqueNames& li) {
        // According to [clang docs](https://clang.llvm.org/doxygen/classclang_1_1CXXBindTemporaryExpr.html),
        // a CXXBindTemporary node "represents binding an expression to a temporary.
        // This ensures the destructor is called for the temporary.
        // It should only be needed for non-POD, non-trivially destructable class types."
        // We can omit these nodes because in our semantics, objects are *always* deleted with
        // destructors, even if the destructor is trivial. Thus, our semantics
        // essentially implicitly has a [BindTemporary] node around all automatic
        // storage duration aggregates.

        cprint.printExpr(expr->getSubExpr(), print, li);
    }

    void VisitOpaqueValueExpr(const OpaqueValueExpr* expr, CoqPrinter& print,
                              ClangPrinter& cprint, const ASTContext&,
                              OpaqueNames& li) {
        print.ctor("Eopaque_ref") << li.find(expr);
        done(expr, print, cprint, Done::VT);
    }

    void VisitAtomicExpr(const clang::AtomicExpr* expr, CoqPrinter& print,
                         ClangPrinter& cprint, const ASTContext&,
                         OpaqueNames& li) {
        print.ctor("Eatomic");

        switch (expr->getOp()) {
#define BUILTIN(ID, TYPE, ATTRS)
#define ATOMIC_BUILTIN(ID, TYPE, ATTRS)                                        \
    case clang::AtomicExpr::AO##ID:                                            \
        print.output() << "AO" #ID << fmt::nbsp;                               \
        break;
#include "clang/Basic/Builtins.def"
#undef BUILTIN
#undef ATOMIC_BUILTIN
        }

        print.begin_list();
        for (unsigned i = 0; i < expr->getNumSubExprs(); ++i) {
            cprint.printExpr(expr->getSubExprs()[i], print, li);
            print.cons();
        }
        print.end_list();

        done(expr, print, cprint);
    }

    void VisitCXXDefaultInitExpr(const CXXDefaultInitExpr* expr,
                                 CoqPrinter& print, ClangPrinter& cprint,
                                 const ASTContext&, OpaqueNames& li) {
        print.ctor("Edefault_init_expr");
        cprint.printExpr(expr->getExpr(), print, li);
        print.end_ctor();
    }

    void VisitVAArgExpr(const VAArgExpr* expr, CoqPrinter& print,
                        ClangPrinter& cprint, const ASTContext&,
                        OpaqueNames& li) {
        print.ctor("Eva_arg");
        cprint.printExpr(expr->getSubExpr(), print, li);
        done(expr, print, cprint);
    }

    void VisitLambdaExpr(const LambdaExpr* expr, CoqPrinter& print,
                         ClangPrinter& cprint, const ASTContext&,
                         OpaqueNames&) {
        print.ctor("Eunsupported");
        print.str("lambda");
        done(expr, print, cprint, Done::VT);
    }

    void VisitImplicitValueInitExpr(const ImplicitValueInitExpr* expr,
                                    CoqPrinter& print, ClangPrinter& cprint,
                                    const ASTContext& ctxt, OpaqueNames&) {
        print.ctor("Eimplicit_init");
        done(expr, print, cprint);
    }

    void VisitCXXPseudoDestructorExpr(const CXXPseudoDestructorExpr* expr,
                                      CoqPrinter& print, ClangPrinter& cprint,
                                      const ASTContext& ctxt, OpaqueNames&) {
        print.ctor("Epseudo_destructor");
        cprint.printQualType(expr->getDestroyedType(), print);
        print.output() << fmt::nbsp;
        cprint.printExpr(expr->getBase(), print);
        print.end_ctor();
    }

    void VisitCXXNoexceptExpr(const CXXNoexceptExpr* expr, CoqPrinter& print,
                              ClangPrinter& cprint, const ASTContext&,
                              OpaqueNames&) {
        // note: i should record the fact that this is a noexcept expression
        print.ctor("Ebool");
        print.boolean(expr->getValue());
        print.end_ctor();
    }

    void VisitTypeTraitExpr(const TypeTraitExpr* expr, CoqPrinter& print,
                            ClangPrinter& cprint, const ASTContext&,
                            OpaqueNames&) {
        // note: i should record the fact that this is a noexcept expression
        print.ctor("Ebool");
        print.boolean(expr->getValue());
        print.end_ctor();
    }

    void VisitCXXScalarValueInitExpr(const CXXScalarValueInitExpr* expr,
                                     CoqPrinter& print, ClangPrinter& cprint,
                                     const ASTContext&, OpaqueNames&) {
        print.ctor("Eimplicit_init");
        cprint.printQualType(expr->getType(), print);
        print.end_ctor();
    }

    void VisitArrayInitLoopExpr(const ArrayInitLoopExpr* expr,
                                CoqPrinter& print, ClangPrinter& cprint,
                                const ASTContext&, OpaqueNames& li) {
        print.ctor("Earrayloop_init");

        auto index = li.fresh(expr->getCommonExpr());
        print.output() << index << fmt::nbsp;

        // this is the source array which we are initializing
        auto src = expr->getCommonExpr()->getSourceExpr();
        cprint.printExpr(src, print, li);

        // this is the expression that is evaluated
        li.inc_index_count();
        print.output() << li.index_count() << fmt::nbsp << expr->getArraySize()
                       << fmt::nbsp;
        cprint.printExpr(expr->getSubExpr(), print, li);
        li.dec_index_count();
        li.free(expr->getCommonExpr()); // index goes out of scope at this point

        done(expr, print, cprint);
    }

    void VisitArrayInitIndexExpr(const ArrayInitIndexExpr* expr,
                                 CoqPrinter& print, ClangPrinter& cprint,
                                 const ASTContext&, OpaqueNames& li) {
        print.ctor("Earrayloop_index") << li.index_count() << fmt::nbsp;
        done(expr, print, cprint);
    }
};

PrintExpr PrintExpr::printer;

void
ClangPrinter::printExpr(const clang::Expr* expr, CoqPrinter& print,
                        OpaqueNames& li) {
    auto depth = print.output().get_depth();
    PrintExpr::printer.Visit(expr, print, *this, *this->context_, li);
    if (depth != print.output().get_depth()) {
        using namespace logging;
        fatal() << "Error: BUG indentation bug in during: "
                << expr->getStmtClassName() << "\n";
        assert(false);
    }
}

void
ClangPrinter::printExpr(const clang::Expr* expr, CoqPrinter& print) {
    OpaqueNames names;
    printExpr(expr, print, names);
}
