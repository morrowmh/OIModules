-- Cache for storing OI-resolutions
oiResCache = new MutableHashTable

-- Should be of the form {dd => List, modules => List}
OIResolution = new Type of HashTable

net OIResolution := C -> (
    N := "0: " | toString C.modules#0;
    for i from 1 to #C.modules - 1 do N = N || toString i | ": " | toString C.modules#i;
    N
)

describe OIResolution := C -> (
    N := "0: Module: " | net C.modules#0 || "Differential: " | net C.dd#0;
    for i from 1 to #C.modules - 1 do N = N || toString i | ": Module: " | net C.modules#i || "Differential: " | net C.dd#i;
    N
)

ranks = method(TypicalValue => Net)
ranks OIResolution := C -> (
    N := "0: rank " | toString getRank C.modules#0;
    for i from 1 to #C.modules - 1 do N = N || toString i | ": rank " | toString getRank C.modules#i;
    N
)

OIResolution _ ZZ := (C, n) -> C.modules#n

-- Compute an OI-resolution of length n for the OI-module generated by L
oiRes = method(TypicalValue => OIResolution, Options => {Verbose => false, Strategy => Minimize, TopNonminimal => false})
oiRes(List, ZZ) := opts -> (L, n) -> (
    if not (opts.Verbose === true or opts.Verbose === false) then error "expected Verbose => true or Verbose => false";
    if not (opts.TopNonminimal === true or opts.TopNonminimal === false) then error "expected TopNonminimal => true or TopNonminimal => false";
    if not (opts.Strategy === FastNonminimal or opts.Strategy === Minimize or opts.Strategy === Reduce) then
        error "expected Strategy => FastNonminimal or Strategy => Minimize or Strategy => Reduce";
    
    if n < 0 then error "expected a nonnegative integer";

    if opts.Verbose then print "Computing OI-resolution";

    -- Return the resolution if it already exists
    if oiResCache#?(L, n, opts.Strategy, opts.TopNonminimal) then return oiResCache#(L, n, opts.Strategy, opts.TopNonminimal);

    strat := opts.Strategy;
    if n === 0 and opts.TopNonminimal then strat = FastNonminimal;
    oigb := oiGB(L, Verbose => opts.Verbose, Strategy => strat);
    currentGB := oigb;

    ddMut := new MutableList;
    modulesMut := new MutableList;
    groundFreeOIMod := getFreeOIModule currentGB#0;
    e := groundFreeOIMod.basisSym;
    currentSymbol := getSymbol concatenate(e, "0");
    count := 0;

    if n > 0 then for i to n - 1 do (
            if opts.Verbose then print "\n----------------------------------------\n----------------------------------------\n";

            if i === n - 1 and opts.TopNonminimal then strat = FastNonminimal;
            syzGens := oiSyz(currentGB, currentSymbol, Verbose => opts.Verbose, Strategy => strat);

            if #syzGens === 0 then break;
            count = count + 1;

            targFreeOIMod := getFreeOIModule currentGB#0;
            srcFreeOIMod := getFreeOIModule syzGens#0;

            modulesMut#i = srcFreeOIMod;
            ddMut#i = new FreeOIModuleMap from {srcMod => srcFreeOIMod, targMod => targFreeOIMod, genImages => currentGB};

            currentGB = syzGens;
            currentSymbol = getSymbol concatenate(e, toString count)
    );

    -- Append the last term in the sequence
    shifts := for elt in currentGB list -degree elt;
    widths := for elt in currentGB list getWidth elt;
    modulesMut#count = makeFreeOIModule(currentSymbol, widths, groundFreeOIMod.polyOIAlg, DegreeShifts => shifts, OIMonomialOrder => currentGB);
    ddMut#count = new FreeOIModuleMap from {srcMod => modulesMut#count, targMod => if count === 0 then groundFreeOIMod else modulesMut#(count - 1), genImages => currentGB};

    -- Cap the sequence with zeros
    for i from count + 1 to n do (
        currentSymbol = getSymbol concatenate(e, toString i);
        modulesMut#i = makeFreeOIModule(currentSymbol, {}, groundFreeOIMod.polyOIAlg);
        ddMut#i = new FreeOIModuleMap from {srcMod => modulesMut#i, targMod => modulesMut#(i - 1), genImages => {}}
    );

    -- Minimize the resolution
    if #ddMut > 1 and not isZero ddMut#1 then (
        if opts.Verbose then print "\n----------------------------------------\n----------------------------------------\n\nMinimizing resolution...";

        done := false;
        while not done do (
            done = true;

            -- Look for units on identity basis elements
            unitFound := false;
            local data;
            for i from 1 to #ddMut - 1 do (
                ddMap := ddMut#i;
                if isZero ddMap then continue;
                
                srcFreeOIMod := ddMap.srcMod;
                targFreeOIMod := ddMap.targMod;
                for j to #ddMap.genImages - 1 do (
                    if isZero ddMap.genImages#j then continue;

                    for single in keyedSingles ddMap.genImages#j do if (single.key#0).img === toList(1..(single.key#0).targWidth) and isUnit single.vec#(single.key) then (
                        unitFound = true;
                        done = false;
                        data = {i, j, single};
                        if opts.Verbose then print("Unit found on term: " | net single.vec);
                        break
                    );

                    if unitFound then break
                );

                if unitFound then break
            );

            -- Prune the sequence
            if unitFound then (
                if opts.Verbose then print "Pruning...";

                unitSingle := data#2;
                targBasisPos := unitSingle.key#1 - 1;
                srcBasisPos := data#1;
                ddMap := ddMut#(data#0);
                srcFreeOIMod := ddMap.srcMod;
                targFreeOIMod := ddMap.targMod;

                -- Make the new free OI-modules
                newSrcWidths := sdrop(srcFreeOIMod.genWidths, srcBasisPos);
                newSrcShifts := sdrop(srcFreeOIMod.degShifts, srcBasisPos);
                newTargWidths := sdrop(targFreeOIMod.genWidths, targBasisPos);
                newTargShifts := sdrop(targFreeOIMod.degShifts, targBasisPos);
                newSrcFreeOIMod := makeFreeOIModule(srcFreeOIMod.basisSym, newSrcWidths, srcFreeOIMod.polyOIAlg, DegreeShifts => newSrcShifts);
                newTargFreeOIMod := makeFreeOIModule(targFreeOIMod.basisSym, newTargWidths, targFreeOIMod.polyOIAlg, DegreeShifts => newTargShifts);

                -- Compute the new differential
                newGenImages := for i to #srcFreeOIMod.genWidths - 1 list (
                    if i === srcBasisPos then continue;

                    -- Calculate the stuff to subtract off
                    thingToSubtract := makeZero getModuleInWidth(srcFreeOIMod, srcFreeOIMod.genWidths#i);
                    for single in keyedSingles ddMap.genImages#i do (
                        if not single.key#1 === targBasisPos + 1 then continue;

                        modMap := getInducedModuleMap(srcFreeOIMod, single.key#0);
                        basisElt := getBasisElement(srcFreeOIMod, srcBasisPos);
                        thingToSubtract = thingToSubtract + single.vec#(single.key) * modMap basisElt
                    );

                    -- Calculate the new image
                    basisElt := getBasisElement(srcFreeOIMod, i);
                    newGenImage0 := ddMap(basisElt - lift(1 // unitSingle.vec#(unitSingle.key), srcFreeOIMod.polyOIAlg.baseField) * thingToSubtract);
                    M := getModuleInWidth(newTargFreeOIMod, getWidth newGenImage0);
                    newGenImage := makeZero M;
                    for newSingle in keyedSingles newGenImage0 do (
                        idx := newSingle.key#1;
                        if idx > targBasisPos + 1 then idx = idx - 1; -- Relabel
                        newGenImage = newGenImage + makeSingle(M, (newSingle.key#0, idx), newSingle.vec#(newSingle.key))
                    );

                    newGenImage
                );

                ddMut#(data#0) = new FreeOIModuleMap from {srcMod => newSrcFreeOIMod, targMod => newTargFreeOIMod, genImages => newGenImages};
                modulesMut#(data#0) = newSrcFreeOIMod;
                modulesMut#(data#0 - 1) = newTargFreeOIMod;

                -- Adjust the map to the right
                ddMap = ddMut#(data#0 - 1);
                ddMut#(data#0 - 1) = new FreeOIModuleMap from {srcMod => newTargFreeOIMod, targMod => ddMap.targMod, genImages => sdrop(ddMap.genImages, targBasisPos)}; -- Restriction

                -- Adjust the map to the left
                if data#0 < #ddMut - 1 then (
                    ddMap = ddMut#(data#0 + 1);
                    newGenImages = new MutableList;

                    for i to #ddMap.genImages - 1 do (
                        M := getModuleInWidth(newSrcFreeOIMod, getWidth ddMap.genImages#i);
                        newGenImage := makeZero M;
                        for single in keyedSingles ddMap.genImages#i do (
                            idx := single.key#1;
                            if idx === srcBasisPos + 1 then continue; -- Projection
                            if idx > srcBasisPos + 1 then idx = idx - 1; -- Relabel
                            newGenImage = newGenImage + makeSingle(M, (single.key#0, idx), single.vec#(single.key))
                        );

                        newGenImages#i = newGenImage
                    );

                    ddMut#(data#0 + 1) = new FreeOIModuleMap from {srcMod => ddMap.srcMod, targMod => newSrcFreeOIMod, genImages => new List from newGenImages}
                )
            )
        )
    );

    -- Store the resolution
    oiResCache#(L, n, opts.Strategy, opts.TopNonminimal) = new OIResolution from {dd => new List from ddMut, modules => new List from modulesMut}
)

-- Verify that an OIResolution is a complex
isComplex = method(TypicalValue => Boolean, Options => {Verbose => false})
isComplex OIResolution := opts -> C -> (
    if #C.dd < 2 then error "expected a sequence with at least two maps";

    -- Check if the maps compose to zero
    for i from 1 to #C.dd - 1 do (
        modMap0 := C.dd#(i - 1);
        modMap1 := C.dd#i;
        if isZero modMap0 or isZero modMap1 then continue;

        for basisElt in getBasisElements modMap1.srcMod do (
            result := modMap0 modMap1 basisElt;

            if opts.Verbose then print(net basisElt | " maps to " | net result);
            
            if not isZero result then (
                if opts.Verbose then print("Found nonzero image: " | net result);
                return false
            )
        )
    );

    true
)