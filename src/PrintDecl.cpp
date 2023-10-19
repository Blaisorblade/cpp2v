/*
 * Copyright (c) 2020 BedRock Systems, Inc.
 * This software is distributed under the terms of the BedRock Open-Source License.
 * See the LICENSE-BedRock file in the repository root for details.
 */
#include "ClangPrinter.hpp"
#include "CoqPrinter.hpp"
#include "DeclVisitorWithArgs.h"
#include "Formatter.hpp"
#include "Logging.hpp"
#include "config.hpp"
#include "clang/AST/Decl.h"
#include "clang/AST/RecordLayout.h"
#include "clang/Basic/Builtins.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Sema/Sema.h"

using namespace clang;

CallingConv
getCallingConv(const Type *type) {
    if (auto ft = dyn_cast_or_null<FunctionType>(type)) {
        return ft->getCallConv();
    } else if (auto at = dyn_cast_or_null<AttributedType>(type)) {
        return getCallingConv(at->getModifiedType().getTypePtr());
    } else if (auto toe = dyn_cast_or_null<TypeOfExprType>(type)) {
        return getCallingConv(toe->desugar().getTypePtr());
    } else {
        type->dump();
        assert(false && "FunctionDecl type is not FunctionType");
        LLVM_BUILTIN_UNREACHABLE;
    }
}

CallingConv
getCallingConv(const FunctionDecl *decl) {
    return getCallingConv(decl->getType().getTypePtr());
}

void
PrintBuiltin(Builtin::ID id, const ValueDecl *decl, CoqPrinter &print,
             ClangPrinter &cprint) {
    switch (id) {
#define CASEB(x)                                                               \
    case Builtin::BI__builtin_##x:                                             \
        print.output() << "Bin_" #x;                                           \
        break;
        CASEB(alloca)
        CASEB(alloca_with_align)
        CASEB(launder)
        // control flow
        CASEB(expect)
        CASEB(unreachable)
        CASEB(trap)
        // bitwise operations
        CASEB(bswap16)
        CASEB(bswap32)
        CASEB(bswap64)
        CASEB(ffs)
        CASEB(ffsl)
        CASEB(ffsll)
        CASEB(clz)
        CASEB(clzl)
        CASEB(clzll)
        CASEB(ctz)
        CASEB(ctzl)
        CASEB(ctzll)
        CASEB(popcount)
        CASEB(popcountl)
        // memory operations
        CASEB(memset)
        CASEB(memcmp)
        CASEB(bzero)
#undef CASEB
    default:
        print.output() << "(Bin_unknown ";
        print.str(decl->getNameAsString());
        print.output() << ")";
        break;
    }
}

static inline Builtin::ID
builtin_id(const Decl *d) {
    if (const FunctionDecl *fd = dyn_cast_or_null<const FunctionDecl>(d)) {
        if (Builtin::ID::NotBuiltin != fd->getBuiltinID()) {
            return Builtin::ID(fd->getBuiltinID());
        }
    }
    return Builtin::ID::NotBuiltin;
}

void
parameter(const ParmVarDecl *decl, CoqPrinter &print, ClangPrinter &cprint) {
    print.output() << fmt::lparen;
    cprint.printParamName(decl, print);
    print.output() << "," << fmt::nbsp;
    cprint.printQualType(decl->getType(), print);
    print.output() << fmt::rparen;
}

const std::string
templateArgumentKindName(TemplateArgument::ArgKind kind) {
#define CASE(k)                                                                \
    case TemplateArgument::ArgKind::k:                                         \
        return #k;
    switch (kind) {
        CASE(Null)
        CASE(Type)
        CASE(Declaration)
        CASE(NullPtr)
        CASE(Integral)
        CASE(Template)
        CASE(TemplateExpansion)
        CASE(Expression)
        CASE(Pack)
    default:
        return "<unknown>";
    }
#undef CASE
}

void
printFunction(const FunctionDecl *decl, CoqPrinter &print,
              ClangPrinter &cprint) {
    print.ctor("Build_Func");

    cprint.printQualType(decl->getReturnType(), print);
    print.output() << fmt::nbsp << fmt::line;

    print.list(decl->parameters(), [&cprint](auto print, auto *i) {
        parameter(i, print, cprint);
    }) << fmt::nbsp;

    cprint.printCallingConv(getCallingConv(decl), print);
    print.output() << fmt::nbsp;
    cprint.printVariadic(decl->isVariadic(), print);
    print.output() << fmt::line;

    if (decl->getBody()) {
        print.ctor("Some", false);
        print.ctor("Impl", false);
        cprint.printStmt(decl->getBody(), print);
        print.end_ctor();
        print.end_ctor();
    } else if (auto builtin = builtin_id(decl)) {
        print.ctor("Some", false);
        print.ctor("Builtin", false);
        PrintBuiltin(builtin, decl, print, cprint);
        print.end_ctor();
        print.end_ctor();
    } else {
        print.output() << "None";
    }
    print.end_ctor();
}

void
printMethod(const CXXMethodDecl *decl, CoqPrinter &print,
            ClangPrinter &cprint) {
    print.ctor("Build_Method");
    cprint.printQualType(decl->getReturnType(), print);
    print.output() << fmt::nbsp;
    cprint.printInstantiatableRecordName(decl->getParent(), print);
    print.output() << fmt::nbsp;
    cprint.printQualifier(decl->isConst(), decl->isVolatile(), print);
    print.output() << fmt::nbsp;

    print.list(decl->parameters(), [&cprint](auto print, auto i) {
        parameter(i, print, cprint);
    }) << fmt::nbsp;

    cprint.printCallingConv(getCallingConv(decl), print);
    print.output() << fmt::nbsp;
    cprint.printVariadic(decl->isVariadic(), print);

    print.output() << fmt::line;
    if (decl->getBody()) {
        print.ctor("Some", false);
        print.ctor("UserDefined");
        cprint.printStmt(decl->getBody(), print);
        print.end_ctor();
        print.end_ctor();
    } else if (decl->isDefaulted()) {
        print.output() << "(Some Defaulted)";
    } else {
        print.output() << "None";
    }

    print.end_ctor();
}

void
printDestructor(const CXXDestructorDecl *decl, CoqPrinter &print,
                ClangPrinter &cprint) {
    auto record = decl->getParent();
    print.ctor("Build_Dtor");
    cprint.printInstantiatableRecordName(record, print);
    print.output() << fmt::nbsp;

    cprint.printCallingConv(getCallingConv(decl), print);
    print.output() << fmt::nbsp;

    if (decl->getBody()) {
        print.some();
        print.ctor("UserDefined");
        cprint.printStmt(decl->getBody(), print);

        print.end_ctor();
        print.end_ctor();
    } else if (decl->isDefaulted()) {
        print.output() << "(Some Defaulted)";
    } else {
        print.output() << fmt::nbsp;
        print.none();
    }

    print.end_ctor();
}

class PrintDecl :
    public ConstDeclVisitorArgs<PrintDecl, bool, CoqPrinter &, ClangPrinter &,
                                const ASTContext &> {
private:
    PrintDecl() = default;

public:
    static PrintDecl printer;

    bool VisitDecl(const Decl *d, CoqPrinter &print, ClangPrinter &cprint,
                   const ASTContext &) {
        using namespace logging;
        fatal() << "Error: visiting declaration..." << d->getDeclKindName()
                << "(at " << cprint.sourceRange(d->getSourceRange()) << ")\n";
        die();
        return false;
    }

    bool VisitTypeDecl(const TypeDecl *type, CoqPrinter &print,
                       ClangPrinter &cprint, const ASTContext &) {
        using namespace logging;
        fatal() << "Error: unsupported type declaration `"
                << type->getDeclKindName() << "(at "
                << cprint.sourceRange(type->getSourceRange()) << ")\n";
        die();
        return false;
    }

    bool VisitEmptyDecl(const EmptyDecl *decl, CoqPrinter &print,
                        ClangPrinter &cprint, const ASTContext &) {
        // ignore
        return false;
    }

    bool VisitTemplateTypeParmDecl(const TemplateTypeParmDecl *param,
                                   CoqPrinter &print, ClangPrinter &cprint,
                                   const ASTContext &) {
        assert(print.templates() && "TemplateTypeParmDecl");

        print.ctor("TypeParam", false);
        print.str(param->getName());
        print.end_ctor();
        return true;
    }

    bool VisitTypedefNameDecl(const TypedefNameDecl *type, CoqPrinter &print,
                              ClangPrinter &cprint, const ASTContext &) {
        if (PRINT_TYPEDEF) {
            if (not templatePreamble("typedef", false, type, print, cprint))
                return false;
            cprint.printTypeName(type, print);
            print.output() << fmt::nbsp;
            cprint.printQualType(type->getUnderlyingType(), print);
            print.end_ctor();
            return true;
        } else {
            return false;
        }
    }

    bool VisitTypeAliasTemplateDecl(const TypeAliasTemplateDecl *type,
                                    CoqPrinter &print, ClangPrinter &cprint,
                                    const ASTContext &) {
        return false;
    }

    bool printMangledFieldName(const FieldDecl *field, CoqPrinter &print,
                               ClangPrinter &cprint) {
        if (field->isAnonymousStructOrUnion()) {
            print.ctor("Nanon", false);
            cprint.printTypeName(field->getType()->getAsCXXRecordDecl(), print);
            print.end_ctor();
        } else {
            print.str(field->getName());
        }
        return true;
    }

    void printFieldInitializer(const FieldDecl *field, CoqPrinter &print,
                               ClangPrinter &cprint) {
        Expr *expr = field->getInClassInitializer();
        if (expr != nullptr) {
            print.some();
            cprint.printExpr(expr, print);
            print.end_ctor();
        } else {
            print.none();
        }
    }

    bool printFields(const CXXRecordDecl *decl, const ASTRecordLayout *layout,
                     CoqPrinter &print, ClangPrinter &cprint) {
        auto i = 0;
        print.list(decl->fields(), [&](auto print, auto field) {
            if (field->isBitField()) {
                logging::fatal()
                    << "Error: bit fields are not supported "
                    << cprint.sourceRange(field->getSourceRange()) << "\n";
                logging::die();
            }
            print.ctor("mkMember", i != 0) << fmt::nbsp;
            printMangledFieldName(field, print, cprint);
            print.output() << fmt::nbsp;
            cprint.printQualType(field->getType(), print);
            print.output() << fmt::nbsp;
            print.boolean(field->isMutable());
            print.output() << fmt::nbsp;
            printFieldInitializer(field, print, cprint);
            print.output() << fmt::nbsp;
            print.ctor("Build_LayoutInfo", false)
                << (layout ? layout->getFieldOffset(i++) : 0) << fmt::rparen
                << fmt::rparen;
        });
        return true;
    }

    bool VisitUnionDecl(const CXXRecordDecl *decl, CoqPrinter &print,
                        ClangPrinter &cprint, const ASTContext &ctxt) {
        assert(decl->getTagKind() == TagTypeKind::TTK_Union);
        if (not templatePreamble("union", false, decl, print, cprint))
            return false;

        cprint.printTypeName(decl, print);
        print.output() << fmt::nbsp;
        if (!decl->isCompleteDefinition()) {
            print.none();
            print.end_ctor();
            return true;
        }

        const auto layout = decl->isDependentContext() ?
                                nullptr :
                                &ctxt.getASTRecordLayout(decl);

        print.some();

        print.ctor("Build_Union");
        printFields(decl, layout, print, cprint);

        print.ctor("DTOR", false);
        cprint.printTypeName(decl, print);
        print.end_ctor() << fmt::nbsp;
        // cprint.printObjName(dtor, print) << fmt::nbsp;

        // trivially destructable
        print.output() << fmt::BOOL(decl->hasTrivialDestructor()) << fmt::nbsp;

        // [operator delete] used to delete allocations of this type.
        if (auto dtor = decl->getDestructor()) {
            if (auto del = dtor->getOperatorDelete()) {
                print.some();
                cprint.printObjName(del, print);
                print.end_ctor();
            } else {
                print.none();
            }
        } else {
            print.none();
        }

        if (layout) {
            print.output() << fmt::line << layout->getSize().getQuantity()
                           << fmt::nbsp << layout->getAlignment().getQuantity()
                           << fmt::nbsp;
        } else {
            print.output() << fmt::line << 0 << fmt::nbsp << 0 << fmt::nbsp;
        }

        print.end_ctor();
        print.end_ctor();
        print.end_ctor();
        return true;
    }

    bool VisitStructDecl(const CXXRecordDecl *decl, CoqPrinter &print,
                         ClangPrinter &cprint, const ASTContext &ctxt) {
        assert(decl->getTagKind() == TagTypeKind::TTK_Class ||
               decl->getTagKind() == TagTypeKind::TTK_Struct);
        if (not templatePreamble("struct", false, decl, print, cprint))
            return false;

        const auto layout = decl->isDependentContext() ?
                                nullptr :
                                &ctxt.getASTRecordLayout(decl);

        cprint.printTypeName(decl, print);
        print.output() << fmt::nbsp;
        if (!decl->isCompleteDefinition()) {
            print.none();
            print.end_ctor();
            return true;
        }

        print.some();
        print.ctor("Build_Struct");

        // print the base classes
        print.list(decl->bases(), [&cprint, layout,
                                   &decl](auto print, CXXBaseSpecifier base) {
            if (base.isVirtual()) {
                logging::unsupported()
                    << "virtual base classes not supported"
                    << " (at " << cprint.sourceRange(decl->getSourceRange())
                    << ")\n";
            }

            auto type = base.getType().getTypePtr();
            if (print.templates()) {
                print.output() << "(";
                cprint.printType(type, print);
                print.output() << ", Build_LayoutInfo 0)";
            } else {
                if (auto rec = type->getAsCXXRecordDecl()) {
                    assert(rec &&
                           "non-templated classes must have Record bases.");
                    print.output() << "(";
                    cprint.printTypeName(rec, print);
                    if (not base.isVirtual()) {
                        print.output()
                            << ", Build_LayoutInfo "
                            << (layout ? layout->getBaseClassOffset(rec)
                                             .getQuantity() :
                                         0)
                            << ")";
                    } else {
                        print.output() << ", Build_LayoutInfo 0)";
                    }

                } else {
                    using namespace logging;
                    fatal()
                        << "Error: base class of '" << decl->getNameAsString()
                        << "' ("
                        << base.getType().getTypePtr()->getTypeClassName()
                        << ") is not a RecordType at "
                        << cprint.sourceRange(decl->getSourceRange()) << "\n";
                    die();
                }
            }
        });

        // print the fields
        print.output() << fmt::line;
        printFields(decl, layout, print, cprint);
        print.output() << fmt::nbsp;

        // print the virtual function table
        print.list_filter(decl->methods(), [&cprint](auto print, auto m) {
            if (not m->isVirtual())
                return false;
            if (m->isPure()) {
                print.output() << "(pure_virt";
            } else {
                print.output() << "(impl_virt";
            }
            print.output() << fmt::nbsp;
            cprint.printObjName(m, print);
            print.output() << ")";
            return true;
        });
        print.output() << fmt::nbsp;

        // print the overrides of this class.
        print.begin_list();
        for (auto m : decl->methods()) {
            if (m->isVirtual() and not m->isPure()) {
                for (auto o : m->overridden_methods()) {
                    print.output() << "(";
                    cprint.printObjName(o, print);
                    print.output() << "," << fmt::nbsp;
                    cprint.printObjName(m, print);
                    print.output() << ")";
                    print.cons();
                }
            }
        }
        print.end_list() << fmt::nbsp;
        print.ctor("DTOR", false);
        cprint.printTypeName(decl, print);
        print.end_ctor() << fmt::nbsp;
        // cprint.printObjName(dtor, print) << fmt::nbsp;

        // trivially destructable
        print.output() << fmt::BOOL(decl->hasTrivialDestructor()) << fmt::nbsp;

        // [operator delete] used to delete allocations of this type.
        if (auto dtor = decl->getDestructor()) {
            if (auto del = dtor->getOperatorDelete()) {
                print.some();
                cprint.printObjName(del, print);
                print.end_ctor();
            } else {
                print.none();
            }
        } else {
            print.none();
        }

        // print the layout information
        print.output() << fmt::line;
        if (decl->isPOD()) {
            print.output() << "POD";
        } else if (decl->isStandardLayout()) {
            print.output() << "Standard";
        } else {
            print.output() << "Unspecified";
        }

        if (layout) {
            // size
            print.output() << fmt::nbsp << layout->getSize().getQuantity();

            // alignment
            print.output() << fmt::nbsp << layout->getAlignment().getQuantity();
        } else {
            // size
            print.output() << fmt::nbsp << 0;

            // alignment
            print.output() << fmt::nbsp << 0;
        }

        print.end_ctor();
        print.end_ctor();
        print.end_ctor();
        return true;
    }

    bool VisitCXXRecordDecl(const CXXRecordDecl *decl, CoqPrinter &print,
                            ClangPrinter &cprinter, const ASTContext &ctxt) {
        auto cprint = cprinter.withDecl(decl);
        if (!decl->isCompleteDefinition()) {
            print.ctor("Dtype");
            cprint.printTypeName(decl, print);
            print.end_ctor();
        } else {
            switch (decl->getTagKind()) {
            case TagTypeKind::TTK_Class:
            case TagTypeKind::TTK_Struct:
                return VisitStructDecl(decl, print, cprint, ctxt);
            case TagTypeKind::TTK_Union:
                return VisitUnionDecl(decl, print, cprint, ctxt);
            case TagTypeKind::TTK_Interface:
            default:
                assert(false && "unknown record tag kind");
            }
        }
        return true;
    }

    bool VisitIndirectFieldDecl(const IndirectFieldDecl *decl,
                                CoqPrinter &print, ClangPrinter &cprint,
                                const ASTContext &) {
        return false;
    }

    // TODO: the current implementation of [printTemplateArgs] does
    // not, yet, support nested records.
    void printTemplateArgs(const FunctionDecl *decl, CoqPrinter &print,
                           ClangPrinter &cprint, bool top = true) {
        printTemplateArgs(decl->getLexicalDeclContext(), print, cprint, false);
        if (auto params = decl->getDescribedTemplateParams()) {
            for (auto decl : params->asArray()) {
                cprint.printDecl(decl, print);
                print.cons();
            }
        }

        if (top)
            print.end_list();
    }

    /* While this is a verbatim copy of the above, introducing a [template]
       here gives flexibility for C++ to use this implementation for
       [CXXDestructorDecl] and [CXXConstructorDecl] which is incorrect.
       We are relying on those dispatching to [CXXMethodDecl].
     */
    void printTemplateArgs(const CXXRecordDecl *decl, CoqPrinter &print,
                           ClangPrinter &cprint, bool top = true) {
        printTemplateArgs(decl->getLexicalParent(), print, cprint, false);

        if (auto params = decl->getDescribedTemplateParams()) {
            for (auto decl : params->asArray()) {
                cprint.printDecl(decl, print);
                print.cons();
            }
        }
        if (top)
            print.end_list();
    }

    void printTemplateArgs(const CXXMethodDecl *decl, CoqPrinter &print,
                           ClangPrinter &cprint, bool top = true) {
        printTemplateArgs(decl->getLexicalParent(), print, cprint, false);
        if (auto params = decl->getDescribedTemplateParams()) {
            for (auto decl : params->asArray()) {
                cprint.printDecl(decl, print);
                print.cons();
            }
        }
        if (top)
            print.end_list();
    }

    void printTemplateArgs(const TypeAliasTemplateDecl *decl, CoqPrinter &print,
                           ClangPrinter &cprint, bool top = true) {
        printTemplateArgs(decl->getTemplatedDecl()->getLexicalDeclContext(),
                          print, cprint, false);
        if (auto params = decl->getTemplateParameters()) {
            for (auto decl : params->asArray()) {
                cprint.printDecl(decl, print);
                print.cons();
            }
        }
        if (top)
            print.end_list();
    }

    void printTemplateArgs(const TypedefNameDecl *decl, CoqPrinter &print,
                           ClangPrinter &cprint, bool top = true) {
        printTemplateArgs(decl->getUnderlyingDecl()->getLexicalDeclContext(),
                          print, cprint, false);
        if (auto params = decl->getDescribedTemplateParams()) {
            for (auto decl : params->asArray()) {
                cprint.printDecl(decl, print);
                print.cons();
            }
        }
        if (top)
            print.end_list();
    }

    void printTemplateArgs(const DeclContext *decl, CoqPrinter &print,
                           ClangPrinter &cprint, bool top = true) {
        if (not decl or isa<TranslationUnitDecl>(decl)) {
            print.begin_list();
        } else if (auto md = dyn_cast<CXXMethodDecl>(decl)) {
            printTemplateArgs(md, print, cprint, top);
        } else if (auto rd = dyn_cast<CXXRecordDecl>(decl)) {
            printTemplateArgs(rd, print, cprint, top);
        } else if (auto fd = dyn_cast<FunctionDecl>(decl)) {
            printTemplateArgs(fd, print, cprint, top);
        } else if (isa<NamespaceDecl>(decl)) {
            print.begin_list();
        } else {
            logging::unsupported()
                << "unsupported context " << decl->getDeclKindName() << "\n";
        }
    }

    template<typename D>
    bool templatePreamble(const char *what, bool cons, const D *decl,
                          CoqPrinter &print, ClangPrinter &cprint) {
        auto mctor = [what, &print](bool t) {
            print.output() << fmt::line;
            auto cont = t ? "_template" : "";
            return print.output()
                   << fmt::lparen << "D" << what << cont << fmt::nbsp;
        };
        if (decl->isTemplated()) {
            if (not print.templates())
                return false;
            if (cons)
                print.cons();
            mctor(true);
            if (decl->isTemplated()) {
                printTemplateArgs(decl, print, cprint);
                print.output() << fmt::nbsp;
            }
        } else {
            if (print.templates())
                return false;
            if (cons)
                print.cons();
            mctor(false);
        }
        return true;
    }

    bool printSpecializationInfo(const FunctionDecl *decl, CoqPrinter &print,
                                 ClangPrinter &cprint) {
        auto info = decl->getTemplateSpecializationInfo();
        if (print.templates() && info) {
            switch (info->getTemplateSpecializationKind()) {
            case TemplateSpecializationKind::TSK_Undeclared:
                return false;

            case TemplateSpecializationKind::TSK_ImplicitInstantiation:
            case TemplateSpecializationKind::TSK_ExplicitSpecialization:
            case TemplateSpecializationKind::
                TSK_ExplicitInstantiationDeclaration:
            case TemplateSpecializationKind::
                TSK_ExplicitInstantiationDefinition: {
                auto tdecl = info->getTemplate();
                auto targs = info->TemplateArguments;
                assert(tdecl &&
                       "FunctionTemplateSpecializationInfo without template");
                assert(targs &&
                       "FunctionTemplateSpecializationInfo without arguments");

                auto function = tdecl->getTemplatedDecl();
                assert(function && "FunctionTemplateDecl without function");

                print.ctor("Dinstantiation");
                cprint.printObjName(decl, print);
                print.output() << fmt::nbsp;
                cprint.printObjName(function, print);
                print.output() << fmt::nbsp;
                print.list(targs->asArray(), [&cprint, &info](auto print,
                                                              auto &arg) {
                    switch (arg.getKind()) {

                    case TemplateArgument::Type:
                        print.ctor("TypeArg");
                        cprint.printQualType(arg.getAsType(), print);
                        print.end_ctor();
                        break;

                    default:
                        using namespace logging;
                        fatal()
                            << cprint.sourceRange(
                                   info->getPointOfInstantiation())
                            << ": "
                            << "error: unsupported template argument kind: "
                            << templateArgumentKindName(arg.getKind()) << "\n";
                        die();
                    }
                });
                print.end_ctor();
                return true;
            }
            default: {
                using namespace logging;
                fatal() << cprint.sourceRange(info->getPointOfInstantiation())
                        << ": "
                        << "error: unsupported template specialization kind: "
                        << info->getTemplateSpecializationKind() << "\n";
                die();
                break;
            }
            }
        }
        return false;
    }
    bool printSpecializationInfo(const CXXMethodDecl *decl, CoqPrinter &print,
                                 ClangPrinter &cprint) {
        if (not print.templates() || decl->isDependentContext())
            return false;
        auto info = decl->getMemberSpecializationInfo();
        auto parent = decl->getParent();
        auto from = decl->getInstantiatedFromMemberFunction();
        if (not from) {
            // if ther is no [from], then Clang might not have generated a body,
            // so th definition will not be useful anyways.
            return false;
        }
        if (auto tparent = dyn_cast<ClassTemplateSpecializationDecl>(parent)) {
            switch (info->getTemplateSpecializationKind()) {
            case TemplateSpecializationKind::TSK_Undeclared:
                return false;

            case TemplateSpecializationKind::TSK_ImplicitInstantiation:
            case TemplateSpecializationKind::TSK_ExplicitSpecialization:
            case TemplateSpecializationKind::
                TSK_ExplicitInstantiationDeclaration:
            case TemplateSpecializationKind::
                TSK_ExplicitInstantiationDefinition: {
                auto &targs = tparent->getTemplateArgs();

                print.ctor("Dinstantiation");
                cprint.printObjName(decl, print);
                print.output() << fmt::nbsp;
                cprint.printObjName(from, print);
                print.output() << fmt::nbsp;
                print.list(targs.asArray(), [&cprint, &info](auto print,
                                                             auto &arg) {
                    switch (arg.getKind()) {

                    case TemplateArgument::Type:
                        print.ctor("TypeArg");
                        cprint.printQualType(arg.getAsType(), print);
                        print.end_ctor();
                        break;

                    default:
                        using namespace logging;
                        fatal()
                            << cprint.sourceRange(
                                   info->getPointOfInstantiation())
                            << ": "
                            << "error: unsupported template argument kind: "
                            << templateArgumentKindName(arg.getKind()) << "\n";
                        die();
                    }
                });
                print.end_ctor();
                return true;
            }
            default: {
                using namespace logging;
                fatal() << cprint.sourceRange(info->getPointOfInstantiation())
                        << ": "
                        << "error: unsupported template specialization kind: "
                        << info->getTemplateSpecializationKind() << "\n";
                die();
                break;
            }
            }
        }
        return false;
    }

    bool VisitFunctionDecl(const FunctionDecl *decl, CoqPrinter &print,
                           ClangPrinter &cprinter, const ASTContext &) {
        auto cprint = cprinter.withDecl(decl);
        bool emit = printSpecializationInfo(decl, print, cprint);
        if (not templatePreamble("function", emit, decl, print, cprint)) {
            return emit;
        }

        cprint.printObjName(decl, print);
        print.output() << fmt::nbsp;
        printFunction(decl, print, cprint);
        print.end_ctor();
        return true;
    }

    bool VisitCXXMethodDecl(const CXXMethodDecl *decl, CoqPrinter &print,
                            ClangPrinter &cprinter, const ASTContext &) {
        auto cprint = cprinter.withDecl(decl);
        bool emit = printSpecializationInfo(decl, print, cprint);
        if (not templatePreamble("method", false, decl, print, cprint)) {
            return emit;
        }
        print.output() << fmt::BOOL(decl->isStatic()) << fmt::nbsp;

        cprint.printObjName(decl, print);
        printMethod(decl, print, cprint);
        print.end_ctor();
        return true;
    }

    bool VisitCXXConstructorDecl(const CXXConstructorDecl *decl,
                                 CoqPrinter &print, ClangPrinter &cprinter,
                                 const ASTContext &) {
        auto cprint = cprinter.withDecl(decl);
        bool emit = printSpecializationInfo(decl, print, cprint);
        if (not templatePreamble("constructor", false, decl, print, cprint))
            return emit;

        cprint.printObjName(decl, print);
        print.output() << fmt::nbsp;
        print.ctor("Build_Ctor");
        cprint.printInstantiatableRecordName(decl->getParent(), print);
        print.output() << fmt::line;

        print.list(decl->parameters(), [&cprint](auto print, auto i) {
            parameter(i, print, cprint);
        });
        print.output() << fmt::nbsp;

        cprint.printCallingConv(getCallingConv(decl), print);
        print.output() << fmt::nbsp;

        cprint.printVariadic(decl->isVariadic(), print);

        if (decl->getBody()) {
            print.some();
            print.ctor("UserDefined");
            print.begin_tuple();

            // print the initializer list
            // note that implicit initialization is represented explicitly in this list
            // also, the order is corrrect with respect to initalization order
            print.begin_list();
            // note that not all fields are listed.
            for (auto init : decl->inits()) {
                print.ctor("Build_Initializer");
                if (init->isMemberInitializer()) {
                    print.ctor("InitField", false)
                        << "\"" << init->getMember()->getNameAsString() << "\"";
                    print.end_ctor();
                } else if (init->isBaseInitializer()) {
                    print.ctor("InitBase", false);
                    cprint.printTypeName(
                        init->getBaseClass()->getAsCXXRecordDecl(), print);
                    print.end_ctor();
                } else if (init->isIndirectMemberInitializer()) {
                    auto im = init->getIndirectMember();
                    print.ctor("InitIndirect", false);

                    __attribute__((unused)) bool completed = false;
                    print.begin_list();
                    for (auto i : im->chain()) {
                        if (i->getName() == "") {
                            if (const FieldDecl *field =
                                    dyn_cast<FieldDecl>(i)) {
                                print.begin_tuple();
                                printMangledFieldName(field, print, cprint);
                                print.next_tuple();
                                cprint.printTypeName(
                                    field->getType()->getAsCXXRecordDecl(),
                                    print);
                                print.end_tuple();
                                print.cons();
                            } else {
                                assert(false && "indirect field decl contains "
                                                "non FieldDecl");
                            }
                        } else {
                            completed = true;
                            print.end_list();
                            print.output() << fmt::nbsp;
                            print.str(i->getName());
                            break;
                        }
                    }
                    assert(completed && "didn't find a named field");

                    print.end_ctor();
                } else if (init->isDelegatingInitializer()) {
                    print.output() << "InitThis";
                } else {
                    assert(false && "unknown initializer type");
                }
                print.output() << fmt::line;
                if (init->getMember()) {
                    cprint.printQualType(init->getMember()->getType(), print);
                } else if (init->getIndirectMember()) {
                    cprint.printQualType(init->getIndirectMember()->getType(),
                                         print);
                } else if (init->getBaseClass()) {
                    cprint.printType(init->getBaseClass(), print);
                } else if (init->isDelegatingInitializer()) {
                    cprint.printQualType(decl->getThisType(), print);
                } else {
                    assert(false && "not member, base class, or indirect");
                }
                cprint.printExpr(init->getInit(), print);
                print.end_ctor();
                print.cons();
            }
            print.end_list();
            print.next_tuple();
            cprint.printStmt(decl->getBody(), print);
            print.end_tuple();
            print.end_ctor();
            print.end_ctor();
        } else {
            print.output() << fmt::nbsp;
            print.none();
        }
        print.end_ctor();
        print.end_ctor();
        return true;
    }

    bool VisitCXXDestructorDecl(const CXXDestructorDecl *decl,
                                CoqPrinter &print, ClangPrinter &cprinter,
                                const ASTContext &ctxt) {
        auto cprint = cprinter.withDecl(decl);
        bool emit = printSpecializationInfo(decl, print, cprint);
        if (not templatePreamble("destructor", false, decl, print, cprint))
            return emit;
        cprint.printObjName(decl, print);
        printDestructor(decl, print, cprint);
        print.end_ctor();
        return true;
    }

    bool VisitVarDecl(const VarDecl *decl, CoqPrinter &print,
                      ClangPrinter &cprint, const ASTContext &) {
        // TODO handling of [constexpr] needs to be improved.
        if (decl->isTemplated()) {
            return false;
        } else {
            print.ctor("Dvariable");
            cprint.printObjName(decl, print);
            print.output() << fmt::nbsp;
            cprint.printQualType(decl->getType(), print);
            print.output() << fmt::nbsp;
            if (decl->hasInit()) {
                print.some();
                cprint.printExpr(decl->getInit(), print);
                print.output() << fmt::rparen;
            } else {
                print.none();
            }
            print.end_ctor();
        }
        return true;
    }

    bool VisitUsingDecl(const UsingDecl *decl, CoqPrinter &print,
                        ClangPrinter &cprint, const ASTContext &) {
        return false;
    }

    bool VisitUsingDirectiveDecl(const UsingDirectiveDecl *decl,
                                 CoqPrinter &print, ClangPrinter &cprint,
                                 const ASTContext &) {
        return false;
    }

    bool VisitNamespaceDecl(const NamespaceDecl *decl, CoqPrinter &print,
                            ClangPrinter &cprint, const ASTContext &) {
        print.ctor("Dnamespace")
            /* << "\"" << decl->getNameAsString() << "\"" */
            << fmt::line;
        print.list(decl->decls(), [&cprint](auto &&print, auto d) {
            cprint.printDecl(d, print);
        });
        print.end_ctor();
        return true;
    }

    bool VisitEnumDecl(const EnumDecl *decl, CoqPrinter &print,
                       ClangPrinter &cprint, const ASTContext &) {
        auto t = decl->getIntegerType();
        if (t.isNull()) {
            assert(decl->getIdentifier() && "anonymous forward declaration");
            print.ctor("Dtype");
            cprint.printTypeName(decl, print);
            print.end_ctor();
            return true;
        } else {
            print.ctor("Denum");
            cprint.printTypeName(decl, print);
            print.output() << fmt::nbsp;
            cprint.printQualType(t, print);
            print.output() << fmt::nbsp;

            // TODO the values are not necessary.
            print.list(decl->enumerators(), [](auto &print, auto i) {
                print.str(i->getNameAsString());
            });

            print.end_ctor();
            return true;
        }
    }

    /** The character types that BRiCk represents using character types
     *  [Tchar_]
     */
    static bool isBRiCkCharacter(const BuiltinType *type) {
        switch (type->getKind()) {
        case BuiltinType::Kind::Char_S:
        case BuiltinType::Kind::Char_U:
        case BuiltinType::Kind::WChar_S:
        case BuiltinType::Kind::WChar_U:
        case BuiltinType::Kind::Char16:
        case BuiltinType::Kind::Char8:
        case BuiltinType::Kind::Char32:
            return true;
        default:
            return false;
        }
    }

    static uint64_t toBRiCkCharacter(size_t bitsize, int64_t val) {
        return static_cast<uint64_t>(val) & ((1ull << bitsize) - 1);
    }

    bool VisitEnumConstantDecl(const EnumConstantDecl *decl, CoqPrinter &print,
                               ClangPrinter &cprint, const ASTContext &) {
        assert(not decl->getNameAsString().empty());
        auto ed = dyn_cast<EnumDecl>(decl->getDeclContext());
        print.ctor("Denum_constant");
        cprint.printObjName(decl, print);
        print.output() << fmt::nbsp;
        cprint.printQualType(decl->getType(), print);
        print.output() << fmt::nbsp;
        cprint.printQualType(ed->getIntegerType(), print);
        auto bt = ed->getIntegerType().getTypePtr()->getAs<BuiltinType>();
        assert(bt && "integer type of enumeration must be a builtin type");

        print.output() << fmt::nbsp << "(";
        if (isBRiCkCharacter(bt)) {
            print.output() << "inl "
                           << toBRiCkCharacter(cprint.getTypeSize(bt),
                                               decl->getInitVal().getExtValue())
                           << "%N";
        } else {
            print.output() << "inr " << decl->getInitVal();
        }
        print.output() << ")" << fmt::nbsp;

        if (decl->getInitExpr()) {
            print.some();
            cprint.printExpr(decl->getInitExpr(), print);
            print.end_ctor();
        } else {
            print.none();
        }

        print.end_ctor();
        return true;
    }

    bool VisitLinkageSpecDecl(const LinkageSpecDecl *decl, CoqPrinter &print,
                              ClangPrinter &cprint, const ASTContext &) {
        // we never print these things.
        assert(false);
        return false;
    }

    bool VisitFunctionTemplateDecl(const FunctionTemplateDecl *decl,
                                   CoqPrinter &print, ClangPrinter &cprint,
                                   const ASTContext &ctxt) {
        assert(print.templates() && "FunctionTemplateDecl");

        //auto params = decl->getTemplateParameters();
        //assert(params && "FunctionTemplateDecl without parameters");
        auto function = decl->getTemplatedDecl();
        assert(function && "FunctionTemplateDecl without function");

        return this->Visit(function, print, cprint, ctxt);
    }

    bool VisitClassTemplateDecl(const ClassTemplateDecl *decl,
                                CoqPrinter &print, ClangPrinter &cprint,
                                const ASTContext &ctxt) {
        assert(print.templates() && "unexpected class template");

        if (true)
            return this->Visit(decl->getTemplatedDecl(), print, cprint, ctxt);
        else {
            using namespace logging;
            unsupported() << cprint.sourceRange(decl->getSourceRange()) << ": "
                          << "warning: unsupported class template\n";
            return false;
        }
    }

    bool VisitFriendDecl(const FriendDecl *, CoqPrinter &, ClangPrinter &,
                         const ASTContext &) {
        return false;
    }

    bool VisitUsingShadowDecl(const UsingShadowDecl *, CoqPrinter &,
                              ClangPrinter &, const ASTContext &) {
        return false;
    }

    bool VisitStaticAssertDecl(const StaticAssertDecl *decl, CoqPrinter &print,
                               ClangPrinter &cprint, const ASTContext &) {
        print.ctor("Dstatic_assert");
        if (auto msg = decl->getMessage()) {
            print.some();
            print.str(msg->getString()) << fmt::nbsp;
            print.end_ctor();
        } else {
            print.none();
        }
        cprint.printExpr(decl->getAssertExpr(), print);
        print.end_ctor();
        return true;
    }
};

PrintDecl PrintDecl::printer;

bool
ClangPrinter::printDecl(const clang::Decl *decl, CoqPrinter &print) {
    return PrintDecl::printer.Visit(decl, print, *this, *context_);
}
