-- -*- coding: utf-8 -*-

-- PURPOSE: Algorithms for computing Gröbner bases, syzygies and free resolutions for submodules of free OI-modules over Noetherian polynomial OI-algebras
-- PROGRAMMER: Michael Morrow (https://michaelmorrow.org)
-- LAST UPDATED: April 2022

newPackage("OIModules",
    Headline => "Computation in OI-modules over Noetherian OI-algebras",
    Version => "0.1",
    Date => "April 4, 2022",
    Keywords => {"Commutative Algebra"},
    Authors => {
        { Name => "Michael Morrow", HomePage => "https://michaelmorrow.org", Email => "michaelhmorrow98@gmail.com" }
    },
    DebuggingMode => true,
    HomePage => "https://github.com/morrowmh/OIModules"
)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- EXPORTS ---------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

export {
    -- From OI.m2
    "getOIMaps",

    -- "validateWidth",

    -- From PolynomialOIAlgebras.m2
    "PolynomialOIAlgebra",
    "polynomialOIAlgebra",
    "getAlgebraInWidth",
    "getAlgebraMapsBetweenWidths",
    
    -- "validatePolynomialOIAlgebra",
    -- "linearizeVars",

    -- From FreeOIModules.m2
    "FreeOIModule",
    "freeOIModule",
    "getFreeModuleInWidth"
    -- "getModuleMapsBetweenWidths",

    -- "validateFreeOIModule"
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- BODY ------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- FROM: OI.m2 -----------------------------------------------------------------
--------------------------------------------------------------------------------

-- PURPOSE: Check if a given width is valid
-- INPUT: An integer 'n'
-- OUTPUT: Nothing if n is a valid width, otherwise error
-- COMMENT: Unexported
validateWidth = method()
validateWidth ZZ := n -> (
    if n < 0 then error("Expected nonnegative width, not "|toString(n))
)

-- PURPOSE: Get all OI-maps between two widths
-- INPUT: '(m, n)', a width 'm' and a width 'n' with m ≤ n
-- OUTPUT: A list of OI-maps from m to n
-- COMMENT: Returns an empty list if n < m
-- COMMENT: We represent an OI-map from m to n as a length m list with strictly increasing entries in [n]
getOIMaps = method(TypicalValue => List)
getOIMaps(ZZ, ZZ) := (m, n) -> (
    validateWidth m; validateWidth n;
    if n < m then return {};

    ret := new List;
    sets := subsets(set(toList(1..n)), m);
    for s in sets do (
        ret = append(ret, sort(toList(s)))
    );

    ret
)

--------------------------------------------------------------------------------
-- FROM: PolynomialOIAlgebras.m2 -----------------------------------------------
--------------------------------------------------------------------------------

-- Define the new type PolynomialOIAlgebra
PolynomialOIAlgebra = new Type of HashTable
toString PolynomialOIAlgebra := P -> "baseField: "|toString(P#"baseField")|", varRows: "|toString(P#"varRows")|", genWidth: "|toString(P#"genWidth")|", varSym: "|toString(P#"varSym");
net PolynomialOIAlgebra := P -> (
    "Base field: "|net(P#"baseField") ||
    "Number of variable rows: "|net(P#"varRows") ||
    "Generator width: "|net(P#"genWidth") ||
    "Variable symbol: "|net(P#"varSym")
)

-- PURPOSE: Check if a given PolynomialOIAlgebra object is valid
-- INPUT: A PolynomialOIAlgebra 'P'
-- OUTPUT: Nothing if P is a valid PolynomialOIAlgebra object, otherwise error
-- COMMENT: Unexported
validatePolynomialOIAlgebra = method()
validatePolynomialOIAlgebra PolynomialOIAlgebra := P -> (
    if not sort keys P == sort {"baseField", "varRows", "genWidth", "varSym", "algebras", "maps"} or not (instance(P#"algebras", MutableHashTable) and instance(P#"maps", MutableHashTable)) then error "Invalid PolynomialOIAlgebra HashTable keys";
    if not instance(P#"baseField", Ring) or not isField P#"baseField" then error("Expected a field, not "|toString(P#"baseField"));
    if not instance(P#"varRows", ZZ) or P#"varRows" < 1 then error("Expected a positive integer row count, not "|toString(P#"varRows"));
    if not instance(P#"genWidth", ZZ) or not (P#"genWidth" == 0 or P#"genWidth" == 1) then error("Expected generator width of either 0 or 1, not "|toString(P#"genWidth"));
    if not instance(P#"varSym", Symbol) then error("Expected variable symbol, not "|toString(P#"varSym"))
)

-- PURPOSE: Make a new PolynomialOIAlgebra
-- INPUT: '(K, c, d, x)', a field of coefficients 'K', a positive integer 'c' of rows, a generator width 'd' of either 0 or 1, and a symbol 'x'
-- OUTPUT: A PolynomialOIAlgebra made from K, c, d, x
polynomialOIAlgebra = method(TypicalValue => PolynomialOIAlgebra)
polynomialOIAlgebra(Ring, ZZ, ZZ, Symbol) := (K, c, d, x) -> (
    P := new PolynomialOIAlgebra from {"baseField" => K, "varRows" => c, "genWidth" => d, "varSym" => x, "algebras" => new MutableHashTable, "maps" => new MutableHashTable};
    validatePolynomialOIAlgebra P;
    P
)

-- PURPOSE: Get the linearized index of a variable from its row-col position
-- INPUT: '(P, n, i, j)', a PolynomialOIAlgebra 'P', a width 'n', a row 'i' and a column 'j'
-- OUTPUT: The index of x_(i,j) in the list of variables ordered so that in P_n we have x_(i,j) > x_(i',j') iff j > j' or j = j' and i > i'
-- COMMENT: Unexported
linearizeVars = method(TypicalValue => ZZ)
linearizeVars(PolynomialOIAlgebra, ZZ, ZZ, ZZ) := (P, n, i, j) -> (
    validatePolynomialOIAlgebra P;
    validateWidth n;
    if P#"genWidth" == 0 or n == 0 then return null;
    if i < 1 or i > P#"varRows" then error("Expected row between 1 and "|toString(P#"varRows")|", not "|toString(i));
    if j < 1 or j > n then error("Expected column between 1 and "|toString(n)|", not "|toString(j));

    P#"varRows" * (n - j + 1) - i
)

-- PURPOSE: Get the algebra from a PolynomialOIAlgebra in a specified width
-- INPUT: '(P, n)', a PolynomialOIAlgebra 'P' and a width 'n'
-- OUTPUT: P_n, the width n algebra of P
-- COMMENT: We use the "position down over term" monomial order and the standard ZZ-grading
-- COMMENT: "store => false" will not store the algebra in memory (useful for large computations)
getAlgebraInWidth = method(TypicalValue => PolynomialRing, Options => {"store" => true})
getAlgebraInWidth(PolynomialOIAlgebra, ZZ) := opts -> (P, n) -> (
    validatePolynomialOIAlgebra P;
    validateWidth n;
    if not instance(opts#"store", Boolean) then error("Expected \"store\" => true or \"store\" => false, not \"store\" => "|toString(opts#"store"));

    -- Return the algebra if it already exists
    if (P#"algebras")#?n then return (P#"algebras")#n;

    local ret;
    if P#"genWidth" == 0 or n == 0 then ret = P#"baseField"
    else (
        -- Generate variables
        variables := new MutableList;
        for i from 1 to P#"varRows" do
            for j from 1 to n do variables#(linearizeVars(P, n, i, j)) = (P#"varSym")_(i, j);
        
        -- Make a new algebra
        ret = P#"baseField"[variables, Degrees => {#variables:1}, MonomialOrder => {Position => Down, Lex}]
    );

    -- Store the algebra
    if opts#"store" then (P#"algebras")#n = ret;

    ret
)

-- PURPOSE: Get the maps between two algebras in a PolynomialOIAlgebra
-- INPUT: '(P, m, n)', a PolynomialOIAlgebra 'P', a width 'm' and a width 'n' with m ≤ n
-- OUTPUT: A list of the (OI-induced) algebra maps between P_m and P_n, i.e. P(Hom(m, n))
-- COMMENT: Returns an empty list if n < m and returns the identity map if either genWidth=0 or m=0
-- COMMENT: "store => false" will not store the maps in memory (useful for large computations)
getAlgebraMapsBetweenWidths = method(TypicalValue => List, Options => {"store" => true})
getAlgebraMapsBetweenWidths(PolynomialOIAlgebra, ZZ, ZZ) := opts -> (P, m, n) -> (
    validatePolynomialOIAlgebra P;
    validateWidth m; validateWidth n;
    if n < m then error("Expected m ≤ n, not m = "|toString(m)|" and n = "|toString(n));
    if not instance(opts#"store", Boolean) then error("Expected \"store\" => true or \"store\" => false, not \"store\" => "|toString(opts#"store"));

    -- Return the maps if they already exist
    if (P#"maps")#?(m, n) then return (P#"maps")#(m, n);

    targ := getAlgebraInWidth(P, n, "store" => opts#"store");
    src := getAlgebraInWidth(P, m, "store" => opts#"store");

    local ret;
    if P#"genWidth" == 0 or m == 0 then ret = {map(targ, src)}
    else (
        algMaps := new List;
        oiMaps := getOIMaps(m, n);

        -- Generate algebra maps
        for oiMap in oiMaps do (
            subs := new List;

            for j from 1 to m do
                for i from 1 to P#"varRows" do subs = append(subs, src_(linearizeVars(P, m, i, j)) => targ_(linearizeVars(P, n, i, oiMap#(j - 1))));

            algMaps = append(algMaps, map(targ, src, subs))
        );

        ret = algMaps
    );

    -- Store the maps
    if opts#"store" then (P#"maps")#(m, n) = ret;

    ret
)

--------------------------------------------------------------------------------
-- FROM: FreeOIModules.m2 ------------------------------------------------------
--------------------------------------------------------------------------------

-- Define the new type FreeOIModule
-- COMMENT: The lengths of genWidths and degShifts need to be the same
FreeOIModule = new Type of HashTable
net FreeOIModule := F -> (
    "Polynomial OI-Algebra: "|net(toString(F#"alg")) ||
    "Basis symbol: "|net(toString(F#"basisSym")) ||
    "Generator widths: "|net(toString(F#"genWidths")) ||
    "Degree shifts: "|net(toString(F#"degShifts"))
)

-- PURPOSE: Check if a given FreeOIModule object is valid
-- INPUT: A FreeOIModule 'F'
-- OUTPUT: Nothing if F is a valid FreeOIModule object, otherwise error
-- COMMENT: Unexported
validateFreeOIModule = method()
validateFreeOIModule FreeOIModule := F -> (
    if not sort keys F == sort {"alg", "basisSym", "genWidths", "degShifts", "modules", "maps"} or not (instance(F#"modules", MutableHashTable) and instance(F#"maps", MutableHashTable)) then error "Invalid FreeOIModule HashTable keys";
    
    if not instance(F#"alg", PolynomialOIAlgebra) then error("Expected PolynomialOIAlgebra, not "|toString(F#"alg"));
    validatePolynomialOIAlgebra(F#"alg");

    if not instance(F#"basisSym", Symbol) then error("Expected basis symbol, not "|toString(F#"basisSym"));

    if not instance(F#"genWidths", List) then error("Expected type 'List' for genWidths, not "|toString(class(F#"genWidths")));
    for l in F#"genWidths" do if not instance(l, ZZ) then error("Expected a list of integers for genWidths, not "|toString(F#"genWidths"));

    if not instance(F#"degShifts", List) then error("Expected type 'List' for degShifts, not "|toString(class(F#"degShifts")));
    for l in F#"degShifts" do if not instance(l, ZZ) then error("Expected a list of integers for degShifts, not "|toString(F#"degShifts"));

    if not #(F#"genWidths") == #(F#"degShifts") then error "Length of genWidths must equal length of degShifts";
)

-- PURPOSE: Make a new FreeOIModule
-- INPUT: '(P, e, W)', a PolynomialOIAlgebra 'P', a basis symbol 'e' and a list of generator widths 'W'
-- OUTPUT: A FreeOIModule made from P, e, W
-- COMMENT: Default degree shifts are all zero
freeOIModule = method(TypicalValue => FreeOIModule, Options => {"shifts" => 0})
freeOIModule(PolynomialOIAlgebra, Symbol, List) := opts -> (P, e, W) -> (
    shifts := new MutableList;
    if opts#"shifts" === 0 then for i to #W - 1 do shifts#i = 0
    else if instance(opts#"shifts", List) then for i to #(opts#"shifts") - 1 do shifts#i = (opts#"shifts")#i
    else error("Invalid shifts option: "|toString(opts#"shifts"));

    ret := new FreeOIModule from {"alg" => P, "basisSym" => e, "genWidths" => W, "degShifts" => toList(shifts), "modules" => new MutableHashTable, "maps" => new MutableHashTable};
    validateFreeOIModule ret;

    ret
)

-- PURPOSE: Get the free module from a FreeOIModule in a specified width
-- INPUT: '(F, n)', a FreeOIModule 'F' and a width 'n'
-- OUTPUT: The free module F_n
-- COMMENT: "store => false" will not store the module in memory (useful for large computations)
getFreeModuleInWidth = method(TypicalValue => Module, Options => {"store" => true})
getFreeModuleInWidth(FreeOIModule, ZZ) := opts -> (F, n) -> (
    validateFreeOIModule F; validateWidth n;
    if not instance(opts#"store", Boolean) then error("Expected \"store\" => true or \"store\" => false, not \"store\" => "|toString(opts#"store"));

    -- Return the module if it already exists
    if (F#"modules")#?n then return (F#"modules")#n;

    -- Generate the module
    degList := new List;
    for i to #(F#"genWidths") - 1 do degList = append(degList, binomial(n, (F#"genWidths")#i) : (F#"degShifts")#i);
    ret := (getAlgebraInWidth(F#"alg", n, "store" => opts#"store"))^degList;

    -- Store the module
    if opts#"store" then (F#"modules")#n = ret;

    ret
)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- DOCUMENTATION ---------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

beginDocumentation()

doc ///
Node
    Key
        OIModules
    Headline
        Computation in OI-modules over Noetherian polynomial OI-algebras
    Description
        Text
            This package allows one to compute Gröbner bases, syzygies and free resolutions for submodules of free OI-modules over Noetherian polynomial OI-algebras.
///

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- TESTS -----------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------



end