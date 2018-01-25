open Cil
open Feature
module E = Errormsg

let currentFunc : fundec ref = ref (emptyFunction "@dummy")
                                   
let todo () = E.s (E.error "todo")
let error () = E.s (E.error "impossible")

let two = integer 2
let makeArray t = TArray(t, Some two, [])
let mkArraySelect vi e : lval = (Var vi, Index(e, NoOffset))

let dummyLocation = {line = 0; file = ""; byte = 0;}

let dummyMem : varinfo =
  let x =
    makeGlobalVar "dummy_mem" (TArray(charType, Some(integer 1024), [])) in
  x.vstorage <- Static; x

let dummyMem' : exp = mkAddrOrStartOf (var dummyMem)
  

let dummyFun : varinfo =
  makeVarinfo false "dummy_f" (TFun(voidType, Some [], false ,[]))

let dummyFunDecl : fundec =
  let x = emptyFunction "dummy_f" in
  x.svar.vstorage <- Static; x


let addrOfType t : typ =
  typeOf(mkAddrOrStartOf (var (makeVarinfo false "" t)))

let addrOfExp e : typ = addrOfType (typeOf e)
  

let condExp = one

let rec combineExp t op =
  match t with
  | [] -> error ()
  | [x] -> x
  | x :: rest ->
     BinOp(op, x, combineExp rest op, typeOf x)

let mkLNot e =
  UnOp(LNot, e, typeOf e)

let mkLAnd x y =
  BinOp(LAnd, x, y, typeOf x)


let rec fltStmt s cond =
  match s.skind with
  | Instr (x) ->
     s.skind <- Instr(List.flatten (List.map (fun e -> fltInstr e cond) x))
  | Return (eop, loc) -> ()
  | Goto (sr, loc) ->  todo ()
  | ComputedGoto (e, loc) -> todo ()
  | Break (_) ->  todo ()
  | Continue (_) -> todo ()
  | If (e, tb, eb, loc) ->
     let tmp = makeTempVar !currentFunc (typeOf e) in
     let set = mkStmt (Instr([Set(var tmp, e, loc)])) in
     let condition = mkLAnd (Lval(var tmp)) cond in
     let _ = List.iter (fun e -> fltStmt e condition) tb.bstmts in
     let _ = List.iter (fun e -> fltStmt e (mkLNot condition)) eb.bstmts in
     s.skind <- Block(mkBlock (set :: (List.append tb.bstmts eb.bstmts)))
  | Switch (_, _, _, _) ->  todo ()
  | Loop (b, loc, x, y) ->  todo ()
  | Block (b) ->  todo ()
  | TryFinally (_, _, _) ->  todo ()
  | TryExcept (_, _, _, _) ->  todo ()
             
      
and fltInstr t cond =
      match t with
      | Set (l, (Lval(Mem(e), off) as r) , loc) ->
         let s = makeTempVar !currentFunc (makeArray (addrOfExp r)) in
         let s' = makeTempVar !currentFunc (makeArray (addrOfExp r)) in
         [Set(mkArraySelect s zero, dummyMem', loc)
         ; Set(mkArraySelect s one, mkAddrOrStartOf (Mem(e), off), loc)
         ; Set(mkArraySelect s' zero, dummyMem', loc)
         ; Set(mkArraySelect  s' one, mkAddrOrStartOf l, loc)
         ; Set(mkMem (Lval(mkArraySelect s' one)) NoOffset
             , Lval(mkMem (Lval(mkArraySelect s one)) NoOffset)
             , loc)]
      | Set (l, e, loc) ->
         let s = makeTempVar !currentFunc (makeArray (addrOfExp e)) in
         [Set(mkArraySelect s zero, dummyMem', loc)
         ; Set(mkArraySelect s one, mkAddrOrStartOf l, loc)
         ; Set((mkMem (Lval(mkArraySelect s cond)) NoOffset), e, loc)]
      | Call (l, e, es, loc) ->
         let s = makeTempVar !currentFunc (makeArray (addrOfExp e)) in
         let r = match l with
           | Some l ->
              let (t, _, _, _) = splitFunctionType (typeOf e) in
              let s' = makeTempVar !currentFunc (makeArray (addrOfType t)) in
              [Set(mkArraySelect s' zero, dummyMem', loc)
              ; Set(mkArraySelect s' one, mkAddrOrStartOf l, loc)
              ; Set(mkArraySelect s zero, Lval(var dummyFun), loc)
              ; Set(mkArraySelect s one, e, loc)
              ; Call(Some (mkMem (Lval(mkArraySelect s' cond)) NoOffset)
                   , Lval(mkArraySelect s cond)
                   , es
                   , loc)]
           | None -> 
              [Set(mkArraySelect s zero, Lval(var dummyFun), loc)
              ; Set(mkArraySelect s one, e, loc)
              ; Call(None, Lval((mkArraySelect s cond)), es, loc)]
         in
         r
      | Asm (_, _, _, _, _, _) -> todo ()


let scanFunc f =
  currentFunc := f;
  List.iter (fun s -> match s.skind with
                      | If(e, tb, eb, loc) ->
                         let tmp = makeTempVar !currentFunc (typeOf e) in
                         let set = mkStmt (Instr([Set(var tmp, e, loc)])) in
                         let condition = Lval(var tmp) in
                         let _ = List.iter (fun e -> fltStmt e condition) tb.bstmts in
                         let _ = List.iter (fun e -> fltStmt e (mkLNot condition)) eb.bstmts in
                         s.skind <- Block(mkBlock (set :: (List.append tb.bstmts eb.bstmts)))
                      | _ -> ())
    f.sbody.bstmts
    
    
let feature = 
  { fd_name = "flatten";
    fd_enabled = false;
    fd_description = "flatten for fun!" ;
    fd_extraopt = [];
    fd_doit = (function (f : file) -> 
                         let _ = iterGlobals f (fun glob ->
                                     match glob with
                                     | GFun (fd,_) -> scanFunc fd
                                     | _ -> ()) in
                         f.globals <- GFun(dummyFunDecl, dummyLocation) :: f.globals;
                         f.globals <- GVar(dummyMem , {init=None}, dummyLocation) :: f.globals;
              );
    fd_post_check = true;
  }

let () = Feature.register feature
