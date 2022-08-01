open OCamlR

module Stubs = OCamlR_base_stubs
module Stubs2 = OCamlR_base_stubs2

let subset_symbol = symbol "["
let subset2_symbol = symbol ~generic:true "[["
let missing_arg = (Symsxp.missing_arg () :> sexp)

let gen_raw_subset2 label_dec x label =
  call subset2_symbol [
      arg Enc.sexp x ;
      arg label_dec label ;
  ]

let raw_subset2 = gen_raw_subset2 Enc.string
let raw_subset2_i = gen_raw_subset2 Enc.int

let inherits_symbol = symbol "inherits"
let inherits x s =
  call inherits_symbol [
    arg (fun x -> x) x ;
    arg Enc.string s
  ]
  |> Dec.bool

module Environment = struct
  include Envsxp

  let create () =
    Stubs.new'env ()
    |> unsafe_of_sexp

  let get env ~class_ x =
    let y = raw_subset2 (to_sexp env) x in
    let cls = Sexp._class_ y in
    if List.mem class_ cls then Some y
    else None
end

module type Matrix = sig
  include Atomic_vector
  type vector
  val dim : t -> int * int
  val as_vector : t -> vector
  val of_arrays : repr array array -> t
  val get2 : t -> int -> int -> repr
  val get_row : t -> int -> vector
  val get_col : t -> int -> vector
end

module Make_matrix(V : Atomic_vector) = struct
  include V

  let dim (x : t) =
    match Stubs2.dim (to_sexp x) |> Dec.ints with
    | [| i ; j |] -> (i, j)
    | _ -> assert false

  let as_vector x = x

  let of_arrays m =
    let data =
      Array.to_list m
      |> Array.concat
      |> V.of_array
      |> to_sexp
    in
    Stubs.matrix ~data ~nrow:(Enc.int (Array.length m)) ~byrow:(Enc.bool true) ()
    |> unsafe_of_sexp

  let get_row m i =
    call subset_symbol [
      arg V.to_sexp m  ;
      arg Enc.int i ;
      arg Enc.sexp missing_arg ;
    ]
    |> V.unsafe_of_sexp

  let get_col m j =
    call subset_symbol [
      arg V.to_sexp m  ;
      arg Enc.sexp missing_arg ;
      arg Enc.int j ;
    ]
    |> V.unsafe_of_sexp
end

module type Vector = sig
  include Atomic_vector
  val c : t list -> t
  module Matrix : Matrix with type repr := repr
                          and type vector := t
end

module Make_vector(V : Atomic_vector) = struct
  include V
  let c_symbol = symbol "c"
  let c xs =
    call c_symbol (List.map (arg to_sexp) xs)
    |> unsafe_of_sexp
  module Matrix = Make_matrix(V)
end

module Numeric = Make_vector(Realsxp)
module Logical = Make_vector(Lglsxp)
module Integer = Make_vector(Intsxp)
module Character = Make_vector(Strsxp)

module Factor = struct
  include Integer

  let factor_fun = symbol "factor"
  let of_integer xs =
    call factor_fun [ arg Integer.to_sexp xs ]
    |> unsafe_of_sexp
  let of_character xs =
    call factor_fun [ arg Character.to_sexp xs ]
    |> unsafe_of_sexp

  let of_array xs = of_integer (of_array xs)
  let of_list xs = of_integer (of_list xs)
  let of_array_opt xs = of_integer (of_array_opt xs)

  let levels x =
    attr x "levels"
    |> Character.unsafe_of_sexp
end

type matrix = [
  | `Numeric   of Numeric.Matrix.t
  | `Logical   of Logical.Matrix.t
  | `Integer   of Integer.Matrix.t
  | `Factor    of Factor.Matrix.t
  | `Character of Character.Matrix.t
]

let classify_atomic_data x =
  match Sexptype.of_sexp x with
  | IntSxp ->
    if inherits x "factor"
    then Some (`Factor (Factor.unsafe_of_sexp x))
    else Some (`Integer (Integer.unsafe_of_sexp x))
  | RealSxp -> Some (`Numeric (Numeric.unsafe_of_sexp x))
  | StrSxp -> Some (`Character (Character.unsafe_of_sexp x))
  | LglSxp -> Some (`Logical (Logical.unsafe_of_sexp x))
  | _ -> None

module List_ = struct
  include Vecsxp

  let as_vecsxp x = x

  let gen_subset2 subset2 x field dec =
    subset2 (to_sexp x) field
    |> Sexp.nil_map ~f:dec

  let subset2 x field dec = gen_subset2 raw_subset2 x field dec
  let subset2_i x field dec = gen_subset2 raw_subset2_i x field dec

  let gen_subset2_exn f label x field dec =
    match f x field dec with
    | None -> failwith label
    | Some y -> y

  let subset2_exn x field dec = gen_subset2_exn subset2 "subset2_exn" x field dec
  let subset2_i_exn x field dec = gen_subset2_exn subset2_i "subset2_i_exn" x field dec

  let list_symbol = symbol "list"

  let create xs =
    List.map (fun (maybe_label, sexp) -> arg Sexp.to_sexp ?name:maybe_label sexp) xs
    |> call list_symbol
    |> unsafe_of_sexp
end

module Dataframe = struct
  include List_
  let as_list x = x

  let dim x =
    match Stubs.dim'data'frame ~x:(to_sexp x) () |> Dec.ints with
    | [| i ; j |] -> (i, j)
    | _ -> assert false

  let of_env (env : Environment.t) x =
    Environment.get env ~class_:"data.frame" x
    |> Option.map unsafe_of_sexp

  type column = [
      `Numeric of Numeric.t
    | `Integer of Integer.t
    | `Logical of Logical.t
    | `Character of Character.t
    | `Factor of Factor.t
  ]

  let rarg_of_column_data name =
    let f g x = arg g ~name x in
    function
    | `Numeric x -> f Numeric.to_sexp x
    | `Logical x -> f Logical.to_sexp x
    | `Character x -> f Character.to_sexp x
    | `Integer x -> f Integer.to_sexp x
    | `Factor x -> f Factor.to_sexp x

  let create cols =
    List.map
      (fun (label, col) -> rarg_of_column_data label col)
      cols
    |> call (symbol "data.frame")
    |> unsafe_of_sexp

  let rbind x y =
    call Stubs.rbind_symbol [
      arg to_sexp x ;
      arg to_sexp y
    ]
    |> unsafe_of_sexp

  let cbind x y =
    call Stubs.cbind_symbol [
      arg to_sexp x ;
      arg to_sexp y ;
    ]
    |> unsafe_of_sexp

  let get_row m i =
    call subset_symbol [
      arg to_sexp m  ;
      arg Enc.int i ;
      arg Enc.sexp missing_arg ;
    ]
    |> unsafe_of_sexp

  let classify_column x =
    match classify_atomic_data x with
    | Some x -> x
    | None ->
      let msg =
        Printf.sprintf
          "OCamlR_base.Dataframe.classify_column: unsupported %s sexp"
          (Sexptype.to_string (Sexptype.of_sexp x))
    in
    invalid_arg msg

  let get_col m j =
    call subset_symbol [
      arg to_sexp m  ;
      arg Enc.sexp missing_arg ;
      arg Enc.int j ;
    ]
    |> classify_column

  let as'matrix df =
    call Stubs.as'matrix'data'frame_symbol [
      arg to_sexp df ;
    ]
    |> classify_atomic_data
    |> Option.get
end

let sample ?replace ?prob ~size x =
  Stubs.sample
    ~x:(Enc.floats x)
    ~size:(Enc.int size)
    ?replace:(Option.map Enc.bool replace)
    ?prob:(Option.map Enc.floats prob)
    ()
  |> Dec.floats

let readRDS fn =
  Stubs.readRDS ~file:(Enc.string fn) ()

let saveRDS ?ascii ?compress ~file obj =
  Stubs.saveRDS
    ~object_:obj
    ~file:(Enc.string file)
    ?ascii:(Option.map Enc.bool ascii)
    ?compress:(Option.map Enc.bool compress)
    ()
  |> ignore

let table (type s) (module Vector : Vector with type t = s) (x : s) =
  call Stubs.table_symbol [ arg Vector.to_sexp x ]
  |> Integer.unsafe_of_sexp

module Formula = struct
  include Langsxp
end
