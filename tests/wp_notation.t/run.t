  $ . ../setup-project.sh
  $ dune build test.vo
  "~~~TESTING COMPACT NOTATIONS~~~"%bs
       : bs
  NOTATION_wp_nowrap =
  ::wpS
    [region:
      "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
      [this := WpTestDefns.this]; return ptr<void>]
    ({s: ($"foo" + $"bar");
         break; 
         continue; 
         ($"foo" + $"bar");
         ($"foo" + $"bar");
         return; 
         return ($"foo" + $"bar"); 
         // end block})
       : mpred
  NOTATION_wp_wrap =
  ::wpS
    [region:
      "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
      "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
      [this := WpTestDefns.this]; return ptr<void>]
    ({s: ($"foo" + $"bar");
         break; 
         continue; 
         ($"foo" + $"bar");
         ($"foo" + $"bar");
         return; 
         return ($"foo" + $"bar"); 
         // end block
         ($"foo" + $"bar");
         break; 
         continue; 
         ($"foo" + $"bar");
         ($"foo" + $"bar");
         return; 
         return ($"foo" + $"bar"); 
         // end block
         ($"foo" + $"bar");
         break; 
         continue; 
         ($"foo" + $"bar");
         ($"foo" + $"bar");
         return; 
         return ($"foo" + $"bar"); 
         // end block
         ($"foo" + $"bar");
         break; 
         continue; 
         ($"foo" + $"bar");
         ($"foo" + $"bar");
         return; 
         return ($"foo" + $"bar"); 
         // end block
         // end block})
       : mpred
  NOTATION_wp_decl_nowrap =
  λ (decl : VarDecl) (Q : region → FreeTemps → epred),
    ::wpD
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      decl
       : VarDecl → (region → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_decl_nowrap decl%CPP_stmt_scope Q%function_scope
  NOTATION_wp_atomic_nil =
  λ (M : coPset) (Q : val → mpred),
    ::wpAtomic (Mask ↦ M; Type ↦ ptr<void>) {e: {?: expr.AO__atomic_load}()}
       : coPset → (val → mpred) → mpred
  
  Arguments NOTATION_wp_atomic_nil M Q%function_scope
  NOTATION_wp_atomic_cons_nowrap =
  λ (M : coPset) (Q : val → mpred),
    ::wpAtomic
      (Mask ↦ M; Type ↦ ptr<void>) 
      {e: {?: expr.AO__atomic_load}(Vundef, Vundef, Vundef)}
       : coPset → (val → mpred) → mpred
  
  Arguments NOTATION_wp_atomic_cons_nowrap M Q%function_scope
  NOTATION_wp_atomic_cons_wrap =
  λ (M : coPset) (Q : val → mpred),
    ::wpAtomic
      (Mask ↦ M; Type ↦ ptr<void>) 
      {e: {?: expr.AO__atomic_load}(Vundef,
                                    Vundef,
                                    Vundef,
                                    Vundef,
                                    Vundef,
                                    Vundef,
                                    Vundef,
                                    1123784018923740981723509817230984710298374098123740981723490817230984710293840891273489012734089%Z)}
       : coPset → (val → mpred) → mpred
  
  Arguments NOTATION_wp_atomic_cons_wrap M Q%function_scope
  NOTATION_wp_builtin_nil =
  λ Q : val → epred, ::wpBuiltin (Type ↦ ptr<void>) {e: __builtin_popcount()}
       : (val → epred) → mpred
  
  Arguments NOTATION_wp_builtin_nil Q%function_scope
  NOTATION_wp_builtin_cons_nowrap =
  λ Q : val → epred,
    ::wpBuiltin
      (Type ↦ ptr<void>) {e: __builtin_popcount(Vundef, Vundef, Vundef)}
       : (val → epred) → mpred
  
  Arguments NOTATION_wp_builtin_cons_nowrap Q%function_scope
  NOTATION_wp_builtin_cons_wrap =
  λ Q : val → epred,
    ::wpBuiltin
      (Type ↦ ptr<void>) 
      {e: __builtin_popcount(Vundef,
                             Vundef,
                             Vundef,
                             Vundef,
                             Vundef,
                             Vundef,
                             Vundef,
                             1123784018923740981723509817230984710298374098123740981723490817230984710293840891273489012734089%Z)}
       : (val → epred) → mpred
  
  Arguments NOTATION_wp_builtin_cons_wrap Q%function_scope
  NOTATION_wp_destroy_val_nowrap =
  ::destroy_val {pointer: WpTestDefns.p; qualifiers: const; type: ptr<void>}
       : mpred
  NOTATION_wp_destroy_val_wrap =
  λ aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa : ptr,
    ::destroy_val
      {pointer: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
          qualifiers: const;
          type: ptr<void>}
       : ptr → mpred
  
  Arguments NOTATION_wp_destroy_val_wrap
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  NOTATION_destroy_val_nowrap =
  ::destroy_val {pointer: WpTestDefns.p; type: ptr<void>}
       : mpred
  NOTATION_destroy_val_wrap =
  λ aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa : ptr,
    ::destroy_val
      {pointer: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
          type: ptr<void>}
       : ptr → mpred
  
  Arguments NOTATION_destroy_val_wrap
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  NOTATION_interp_nowrap = ::interp { WpTestDefns.free }
       : mpred
  NOTATION_interp_wrap =
  ::interp
    { (((((((((1 |*| 1) |*| 1) |*| 1) |*| 1) |*| 1) |*| 1) |*| 1) |*| 1) |*| 1)
      |*| 1 }
       : mpred
  NOTATION_wp_lval_nowrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpL
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_lval_nowrap Q%function_scope
  NOTATION_wp_lval_wrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpL
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_lval_wrap Q%function_scope
  NOTATION_wp_init_nowrap =
  λ Q : FreeTemps → epred,
    ::wpPRᵢ
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      (Pointer ↦ WpTestDefns.this) 
      ({e: ($"foo" + $"bar")})
       : (FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_init_nowrap Q%function_scope
  NOTATION_wp_init_wrap =
  λ Q : FreeTemps → epred,
    ::wpPRᵢ
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      (Pointer ↦ WpTestDefns.this) 
      ({e: ($"foo" + $"bar")})
       : (FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_init_wrap Q%function_scope
  NOTATION_wp_prval_nowrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpPR
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_prval_nowrap Q%function_scope
  NOTATION_wp_prval_wrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpPR
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_prval_wrap Q%function_scope
  NOTATION_wp_operand_nowrap =
  λ Q : val → FreeTemps → epred,
    ::wpOperand
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (val → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_operand_nowrap Q%function_scope
  NOTATION_wp_operand_wrap =
  λ Q : val → FreeTemps → epred,
    ::wpOperand
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (val → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_operand_wrap Q%function_scope
  NOTATION_wp_xval_nowrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpX
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_xval_nowrap Q%function_scope
  NOTATION_wp_xval_wrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpX
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_xval_wrap Q%function_scope
  NOTATION_wp_glval_nowrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpGL
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_glval_nowrap Q%function_scope
  NOTATION_wp_glval_wrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpGL
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_glval_wrap Q%function_scope
  NOTATION_wp_discard_nowrap =
  λ Q : FreeTemps → mpred,
    ::wpGLₓ
      [region:
        "foo" @ WpTestDefns.p; [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (FreeTemps → mpred) → mpred
  
  Arguments NOTATION_wp_discard_nowrap Q%function_scope
  NOTATION_wp_discard_nowrap =
  λ Q : FreeTemps → mpred,
    ::wpGLₓ
      [region:
        "foo" @ WpTestDefns.p; [this := WpTestDefns.this]; return ptr<void>]
      ({e: ($"foo" + $"bar")})
       : (FreeTemps → mpred) → mpred
  
  Arguments NOTATION_wp_discard_nowrap Q%function_scope
  NOTATION_wp_func =
  λ (tu : translation_unit) (F : Func) (ls : list ptr) (Q : ptr → epred),
    ::wpFunc Q
       : translation_unit → Func → list ptr → (ptr → epred) → mpred
  
  Arguments NOTATION_wp_func tu F ls%list_scope Q%function_scope
  NOTATION_wp_method =
  λ (tu : translation_unit) (M : Method) (ls : list ptr) (Q : ptr → epred),
    ::wpMethod Q
       : translation_unit → Method → list ptr → (ptr → epred) → mpred
  
  Arguments NOTATION_wp_method tu M ls%list_scope Q%function_scope
  NOTATION_wp_ctor =
  λ (tu : translation_unit) (C : Ctor) (ls : list ptr) (Q : ptr → epred),
    ::wpCtor Q
       : translation_unit → Ctor → list ptr → (ptr → epred) → mpred
  
  Arguments NOTATION_wp_ctor tu C ls%list_scope Q%function_scope
  NOTATION_wp_dtor =
  λ (tu : translation_unit) (D : Dtor) (ls : list ptr) (Q : ptr → epred),
    ::wpDtor Q
       : translation_unit → Dtor → list ptr → (ptr → epred) → mpred
  
  Arguments NOTATION_wp_dtor tu D ls%list_scope Q%function_scope
  NOTATION_wp_args_nowrap =
  λ (tys_ar : expr.evaluation_order.t) (es : list (wp.WPE.M ptr)) 
    (Q : list decltype * function_arity),
    ::wpArgs
      ([region:
         "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
         [this := WpTestDefns.this]; return ptr<void>])
       : expr.evaluation_order.t
         → list (wp.WPE.M ptr)
           → list decltype * function_arity
             → list expr.Expr
               → (list ptr → list ptr → FreeTemps → FreeTemps → mpred) → mpred
  
  Arguments NOTATION_wp_args_nowrap tys_ar es%list_scope 
    Q es%list_scope Q%function_scope
  NOTATION_wp_args_wrap =
  λ (tys_ar : expr.evaluation_order.t) (es : list (wp.WPE.M ptr)) 
    (Q : list decltype * function_arity),
    ::wpArgs
      ([region:
         "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
         "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
         [this := WpTestDefns.this]; return ptr<void>])
       : expr.evaluation_order.t
         → list (wp.WPE.M ptr)
           → list decltype * function_arity
             → list expr.Expr
               → (list ptr → list ptr → FreeTemps → FreeTemps → mpred) → mpred
  
  Arguments NOTATION_wp_args_wrap tys_ar es%list_scope 
    Q es%list_scope Q%function_scope
  NOTATION_wp_initialize_nowrap =
  λ Q : FreeTemps → epred,
    ::wpInitialize
      [region:
        "foo" @ WpTestDefns.p; [this := WpTestDefns.this]; return ptr<void>]
      (WpTestDefns.p |-> type_ptrR ptr<void>)
      ({e: ($"foo" + $"bar")})
       : (FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_initialize_nowrap Q%function_scope
  NOTATION_wp_initialize_wrap =
  λ Q : FreeTemps → epred,
    ::wpInitialize
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      (WpTestDefns.p |-> type_ptrR ptr<void>)
      ({e: ($"foo" + $"bar")})
       : (FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_initialize_wrap Q%function_scope
  "~~~TESTING Verbose NOTATIONS~~~"%bs
       : bs
  NOTATION_wp_nowrap =
  ::wpS
    [region:
      "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
      [this := WpTestDefns.this]; return ptr<void>]
    {s: ($"foo" + $"bar");
        break; 
        continue; 
        ($"foo" + $"bar");
        ($"foo" + $"bar");
        return; 
        return ($"foo" + $"bar"); 
        // end block}
    WpTestDefns.K
       : mpred
  NOTATION_wp_wrap =
  ::wpS
    [region:
      "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
      "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
      [this := WpTestDefns.this]; return ptr<void>]
    {s: ($"foo" + $"bar");
        break; 
        continue; 
        ($"foo" + $"bar");
        ($"foo" + $"bar");
        return; 
        return ($"foo" + $"bar"); 
        // end block
        ($"foo" + $"bar");
        break; 
        continue; 
        ($"foo" + $"bar");
        ($"foo" + $"bar");
        return; 
        return ($"foo" + $"bar"); 
        // end block
        ($"foo" + $"bar");
        break; 
        continue; 
        ($"foo" + $"bar");
        ($"foo" + $"bar");
        return; 
        return ($"foo" + $"bar"); 
        // end block
        ($"foo" + $"bar");
        break; 
        continue; 
        ($"foo" + $"bar");
        ($"foo" + $"bar");
        return; 
        return ($"foo" + $"bar"); 
        // end block
        // end block}
    WpTestDefns.K
       : mpred
  NOTATION_wp_decl_nowrap =
  λ (decl : VarDecl) (Q : region → FreeTemps → epred),
    ::wpD
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      decl
      Q
       : VarDecl → (region → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_decl_nowrap decl%CPP_stmt_scope Q%function_scope
  NOTATION_wp_atomic_nil =
  λ (M : coPset) (Q : val → mpred),
    ::wpAtomic (Mask ↦ M; Type ↦ ptr<void>)  {e: expr.AO__atomic_load()} Q
       : coPset → (val → mpred) → mpred
  
  Arguments NOTATION_wp_atomic_nil M Q%function_scope
  NOTATION_wp_atomic_cons_nowrap =
  λ (M : coPset) (Q : val → mpred),
    ::wpAtomic
      (Mask ↦ M; Type ↦ ptr<void>) 
       {e: expr.AO__atomic_load(Vundef, Vundef, Vundef)}
      Q
       : coPset → (val → mpred) → mpred
  
  Arguments NOTATION_wp_atomic_cons_nowrap M Q%function_scope
  NOTATION_wp_atomic_cons_wrap =
  λ (M : coPset) (Q : val → mpred),
    ::wpAtomic
      (Mask ↦ M; Type ↦ ptr<void>) 
       {e: expr.AO__atomic_load(Vundef,
                                Vundef,
                                Vundef,
                                Vundef,
                                Vundef,
                                Vundef,
                                Vundef,
                                1123784018923740981723509817230984710298374098123740981723490817230984710293840891273489012734089%Z)}
      Q
       : coPset → (val → mpred) → mpred
  
  Arguments NOTATION_wp_atomic_cons_wrap M Q%function_scope
  NOTATION_wp_builtin_nil =
  λ Q : val → epred,
    ::wpBuiltin (Type ↦ ptr<void>) {e: {e: __builtin_popcount}()} Q
       : (val → epred) → mpred
  
  Arguments NOTATION_wp_builtin_nil Q%function_scope
  NOTATION_wp_builtin_cons_nowrap =
  λ Q : val → epred,
    ::wpBuiltin
      (Type ↦ ptr<void>) {e: {e: __builtin_popcount}(Vundef, Vundef, Vundef)}
      Q
       : (val → epred) → mpred
  
  Arguments NOTATION_wp_builtin_cons_nowrap Q%function_scope
  NOTATION_wp_builtin_cons_wrap =
  λ Q : val → epred,
    ::wpBuiltin
      (Type ↦ ptr<void>) 
      {e: {e: __builtin_popcount}(Vundef,
                                  Vundef,
                                  Vundef,
                                  Vundef,
                                  Vundef,
                                  Vundef,
                                  Vundef,
                                  1123784018923740981723509817230984710298374098123740981723490817230984710293840891273489012734089%Z)}
      Q
       : (val → epred) → mpred
  
  Arguments NOTATION_wp_builtin_cons_wrap Q%function_scope
  NOTATION_destroy_val_nowrap =
  ::destroy_val {pointer: WpTestDefns.p; type: ptr<void>} WpTestDefns.E
       : mpred
  NOTATION_destroy_val_wrap =
  λ aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa : ptr,
    ::destroy_val
      {pointer: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
          type: ptr<void>}
      WpTestDefns.E
       : ptr → mpred
  
  Arguments NOTATION_destroy_val_wrap
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  NOTATION_interp_nowrap =
  ::interp { WpTestDefns.free }  WpTestDefns.E
       : mpred
  NOTATION_interp_wrap =
  ::interp
    { (((((((((1 |*| 1) |*| 1) |*| 1) |*| 1) |*| 1) |*| 1) |*| 1) |*| 1) |*| 1)
      |*| 1 }
    WpTestDefns.E
       : mpred
  NOTATION_wp_lval_nowrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpL
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_lval_nowrap Q%function_scope
  NOTATION_wp_lval_wrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpL
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_lval_wrap Q%function_scope
  NOTATION_wp_init_nowrap =
  λ Q : FreeTemps → epred,
    ::wpPRᵢ
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      (Pointer ↦ WpTestDefns.this) 
      {e: ($"foo" + $"bar")}
      Q
       : (FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_init_nowrap Q%function_scope
  NOTATION_wp_init_wrap =
  λ Q : FreeTemps → epred,
    ::wpPRᵢ
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      (Pointer ↦ WpTestDefns.this) 
      {e: ($"foo" + $"bar")}
      Q
       : (FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_init_wrap Q%function_scope
  NOTATION_wp_prval_nowrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpPR
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_prval_nowrap Q%function_scope
  NOTATION_wp_prval_wrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpPR
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_prval_wrap Q%function_scope
  NOTATION_wp_operand_nowrap =
  λ Q : val → FreeTemps → epred,
    ::wpOperand
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (val → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_operand_nowrap Q%function_scope
  NOTATION_wp_operand_wrap =
  λ Q : val → FreeTemps → epred,
    ::wpOperand
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (val → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_operand_wrap Q%function_scope
  NOTATION_wp_xval_nowrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpX
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_xval_nowrap Q%function_scope
  NOTATION_wp_xval_wrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpX
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_xval_wrap Q%function_scope
  NOTATION_wp_glval_nowrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpGL
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_glval_nowrap Q%function_scope
  NOTATION_wp_glval_wrap =
  λ Q : ptr → FreeTemps → epred,
    ::wpGL
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (ptr → FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_glval_wrap Q%function_scope
  NOTATION_wp_discard_nowrap =
  λ Q : FreeTemps → mpred,
    ::wpGLₓ
      [region:
        "foo" @ WpTestDefns.p; [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (FreeTemps → mpred) → mpred
  
  Arguments NOTATION_wp_discard_nowrap Q%function_scope
  NOTATION_wp_discard_nowrap =
  λ Q : FreeTemps → mpred,
    ::wpGLₓ
      [region:
        "foo" @ WpTestDefns.p; [this := WpTestDefns.this]; return ptr<void>]
      {e: ($"foo" + $"bar")}
      Q
       : (FreeTemps → mpred) → mpred
  
  Arguments NOTATION_wp_discard_nowrap Q%function_scope
  NOTATION_wp_func =
  λ (tu : translation_unit) (F : Func) (ls : list ptr) (Q : ptr → epred),
    ::wpFunc Q
       : translation_unit → Func → list ptr → (ptr → epred) → mpred
  
  Arguments NOTATION_wp_func tu F ls%list_scope Q%function_scope
  NOTATION_wp_method =
  λ (tu : translation_unit) (M : Method) (ls : list ptr) (Q : ptr → epred),
    ::wpMethod Q
       : translation_unit → Method → list ptr → (ptr → epred) → mpred
  
  Arguments NOTATION_wp_method tu M ls%list_scope Q%function_scope
  NOTATION_wp_ctor =
  λ (tu : translation_unit) (C : Ctor) (ls : list ptr) (Q : ptr → epred),
    ::wpCtor Q
       : translation_unit → Ctor → list ptr → (ptr → epred) → mpred
  
  Arguments NOTATION_wp_ctor tu C ls%list_scope Q%function_scope
  NOTATION_wp_dtor =
  λ (tu : translation_unit) (D : Dtor) (ls : list ptr) (Q : ptr → epred),
    ::wpDtor Q
       : translation_unit → Dtor → list ptr → (ptr → epred) → mpred
  
  Arguments NOTATION_wp_dtor tu D ls%list_scope Q%function_scope
  NOTATION_wp_args_nowrap =
  λ (tys_ar : expr.evaluation_order.t) (es : list (wp.WPE.M ptr)) 
    (Q : list decltype * function_arity),
    ::wpArgs
      [region:
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      Q
       : expr.evaluation_order.t
         → list (wp.WPE.M ptr)
           → list decltype * function_arity
             → list expr.Expr
               → (list ptr → list ptr → FreeTemps → FreeTemps → mpred) → mpred
  
  Arguments NOTATION_wp_args_nowrap tys_ar es%list_scope 
    Q es%list_scope Q%function_scope
  NOTATION_wp_args_wrap =
  λ (tys_ar : expr.evaluation_order.t) (es : list (wp.WPE.M ptr)) 
    (Q : list decltype * function_arity),
    ::wpArgs
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      Q
       : expr.evaluation_order.t
         → list (wp.WPE.M ptr)
           → list decltype * function_arity
             → list expr.Expr
               → (list ptr → list ptr → FreeTemps → FreeTemps → mpred) → mpred
  
  Arguments NOTATION_wp_args_wrap tys_ar es%list_scope 
    Q es%list_scope Q%function_scope
  NOTATION_wp_initialize_nowrap =
  λ Q : FreeTemps → epred,
    ::wpInitialize
      [region:
        "foo" @ WpTestDefns.p; [this := WpTestDefns.this]; return ptr<void>]
      (WpTestDefns.p |-> type_ptrR ptr<void>)
      {e: ($"foo" + $"bar")}
      Q
       : (FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_initialize_nowrap Q%function_scope
  NOTATION_wp_initialize_wrap =
  λ Q : FreeTemps → epred,
    ::wpInitialize
      [region:
        "qux" @ WpTestDefns.p'''; "baz" @ WpTestDefns.p'';
        "bar" @ WpTestDefns.p'; "foo" @ WpTestDefns.p;
        [this := WpTestDefns.this]; return ptr<void>]
      (WpTestDefns.p |-> type_ptrR ptr<void>)
      {e: ($"foo" + $"bar")}
      Q
       : (FreeTemps → epred) → mpred
  
  Arguments NOTATION_wp_initialize_wrap Q%function_scope
