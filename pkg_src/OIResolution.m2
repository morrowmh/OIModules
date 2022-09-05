-- Cache for storing OI-resolutions computed with oiRes
oiResCache = new MutableHashTable

-- Should be of the form {dd => List, modules => List}
OIResolution = new Type of HashTable

net OIResolution := C -> (
    n := "0: "|toString C.modules#0;
    for i from 1 to #C.modules - 1 do n = n || toString i | ": "|toString C.modules#i;
    n
)

describe OIResolution := C -> (
    n := "0: Module: "|net C.modules#0||"Differential: "|net C.dd#0;
    for i from 1 to #C.modules - 1 do n = n || toString i | ": Module: "|net C.modules#i||"Differential: "|net C.dd#i;
    n
)

OIResolution _ ZZ := (C, n) -> C.modules#n

-- Compute an OIResolution of length n for the OI-module generated by the elements of L
oiRes = method(TypicalValue => OIResolution, Options => {FastNonminimal => false, Verbose => false, MinimalOIGB => true})
oiRes(List, ZZ) := opts -> (L, n) -> (
    if n < 0 then error "expected a nonnegative integer";
    if #L == 0 then error "expected a nonempty List";

    -- Return the resolution if it already exists
    if oiResCache#?(L, n, opts.FastNonminimal, opts.MinimalOIGB) then return oiResCache#(L, n, opts.FastNonminimal, opts.MinimalOIGB);

    ddMut := new MutableList;
    modulesMut := new MutableList;

    -- Make the initial resolution
    initialFreeOIMod := freeOIModuleFromElement L#0;
    e := initialFreeOIMod.basisSym;

    if opts.Verbose then print "Computing an OI-Groebner basis...";
    oigb := oiGB(L, Verbose => opts.Verbose, MinimalOIGB => opts.MinimalOIGB);
    currentGB := oigb;
    currentSymbol := getSymbol concatenate(e, "0");
    count := 0;

    if n > 0 then (
        if opts.Verbose then print "----------------------------------------\n----------------------------------------\nComputing syzygies...";
        for i to n - 1 do (
            syzGens := oiSyz(currentGB, currentSymbol, Verbose => opts.Verbose, MinimalOIGB => opts.MinimalOIGB);

            if #syzGens == 0 then break;

            targFreeOIMod := freeOIModuleFromElement currentGB#0;
            srcFreeOIMod := freeOIModuleFromElement syzGens#0;

            modulesMut#i = srcFreeOIMod;
            ddMut#i = makeFreeOIModuleMap(targFreeOIMod, srcFreeOIMod, getMonomialOrder srcFreeOIMod);

            count = i + 1;
            currentGB = syzGens;
            currentSymbol = getSymbol concatenate(e, toString count)
        )
    );

    -- Append the last term in the sequence
    shifts := for elt in currentGB list -degree elt;
    widths := for elt in currentGB list widthOfElement elt;
    modulesMut#count = makeFreeOIModule(initialFreeOIMod.polyOIAlg, currentSymbol, widths, DegreeShifts => flatten shifts, MonomialOrder => currentGB);
    targFreeOIMod := if count == 0 then initialFreeOIMod else modulesMut#(count - 1);
    ddMut#count = makeFreeOIModuleMap(targFreeOIMod, modulesMut#count, currentGB);

    -- Cap the sequence with zero
    if count < n then (
        currentSymbol = getSymbol concatenate(e, toString(count + 1));
        modulesMut#(count + 1) = makeFreeOIModule(initialFreeOIMod.polyOIAlg, currentSymbol, {});
        ddMut#(count + 1) = makeFreeOIModuleMap(modulesMut#count, modulesMut#(count + 1), {})
    );

    -- Minimize the resolution
    if not opts.FastNonminimal and #ddMut > 1 and isHomogeneous ddMut#0 and not isZero ddMut#1 then (
        if opts.Verbose then print "----------------------------------------\n----------------------------------------\nMinimizing resolution...";
        done := false;
        while not done do (
            done = true;

            -- Look for units on identity basis elements
            unitFound := false;
            local data;
            for i from 1 to #ddMut - 1 do (
                ddMap := ddMut#i;
                if isZero ddMap then continue; -- Skip any zero maps
                srcMod := source ddMap;
                targMod := target ddMap;
                for j to #ddMap.genImages - 1 do (
                    if isZero ddMap.genImages#j then continue;
                    oiTerms := getOITermsFromVector(ddMap.genImages#j, CombineLikeTerms => true);
                    for term in oiTerms do (
                        b := term.basisIndex;
                        if b.oiMap.img === toList(1..b.oiMap.targWidth) and isUnit term.ringElement then (
                            unitFound = true;
                            done = false;
                            data = {i, j, term};
                            if opts.Verbose then print("Unit found on term: "|net term);
                            break
                        );
                        if unitFound then break
                    );
                    if unitFound then break
                );
                if unitFound then break
            );

            -- Prune the sequence
            if unitFound then (
                term := data#2;
                targBasisPos := term.basisIndex.idx - 1;
                srcBasisPos := data#1;
                ddMap := ddMut#(data#0);
                srcMod := source ddMap;
                targMod := target ddMap;

                if opts.Verbose then print "Pruning...";

                newSrcWidths := remove(srcMod.genWidths, srcBasisPos);
                newSrcShifts := remove(srcMod.degShifts, srcBasisPos);
                newTargWidths := remove(targMod.genWidths, targBasisPos);
                newTargShifts := remove(targMod.degShifts, targBasisPos);

                -- Make the new modules
                newSrcMod := makeFreeOIModule(srcMod.polyOIAlg, srcMod.basisSym, newSrcWidths, DegreeShifts => newSrcShifts);
                newTargMod := makeFreeOIModule(targMod.polyOIAlg, targMod.basisSym, newTargWidths, DegreeShifts => newTargShifts);

                -- Compute the new differential
                newGenImages := new List;
                if not (isZero newSrcMod or isZero newTargMod) then (
                    targBasisOIMap := makeOIMap(targMod.genWidths#targBasisPos, toList(1..targMod.genWidths#targBasisPos));
                    srcBasisOIMap := makeOIMap(srcMod.genWidths#srcBasisPos, toList(1..srcMod.genWidths#srcBasisPos));
                    newGenImages = for i to #srcMod.genWidths - 1 list (
                        if i == srcBasisPos then continue;
                        stuff := 0_(getFreeModuleInWidth(srcMod, srcMod.genWidths#i));
                        oiMaps := getOIMaps(targMod.genWidths#targBasisPos, srcMod.genWidths#i);

                        -- Calculate the stuff to subtract off
                        if #oiMaps > 0 and not isZero ddMap.genImages#i then (
                            oiTerms := getOITermsFromVector(ddMap.genImages#i, CombineLikeTerms => true);
                            for term in oiTerms do (
                                b := term.basisIndex;
                                if not b.idx == targBasisPos + 1 then continue;

                                local oiMap;
                                for oimap in oiMaps do if b.oiMap === composeOIMaps(oimap, targBasisOIMap) then ( oiMap = oimap; break );

                                modMap := getInducedModuleMap(srcMod, oiMap);
                                basisElt := getVectorFromOITerms {makeBasisElement makeBasisIndex(srcMod, srcBasisOIMap, srcBasisPos + 1)};
                                stuff = stuff + term.ringElement * modMap basisElt
                            )
                        );

                        -- Calculate the new image
                        basisElt := getVectorFromOITerms {makeBasisElement makeBasisIndex(srcMod, makeOIMap(srcMod.genWidths#i, toList(1..srcMod.genWidths#i)), i + 1)};
                        newGenImage0 := ddMap(basisElt - lift(1 // term.ringElement, srcMod.polyOIAlg.baseField) * stuff);
                        newGenImage := 0_(getFreeModuleInWidth(newTargMod, widthOfElement newGenImage0));
                        if not isZero newGenImage0 then (
                            newOITerms := getOITermsFromVector(newGenImage0, CombineLikeTerms => true);
                            for newTerm in newOITerms do (
                                idx := newTerm.basisIndex.idx;
                                if idx > targBasisPos + 1 then idx = idx - 1; -- Relabel
                                newGenImage = newGenImage + getVectorFromOITerms {makeOITerm(newTerm.ringElement, makeBasisIndex(newTargMod, newTerm.basisIndex.oiMap, idx))}
                            )
                        );

                        newGenImage
                    )
                );

                ddMut#(data#0) = makeFreeOIModuleMap(newTargMod, newSrcMod, newGenImages);
                modulesMut#(data#0) = newSrcMod;
                modulesMut#(data#0 - 1) = newTargMod;

                -- Adjust the adjactent differentials
                -- Below map
                ddMap = ddMut#(data#0 - 1);
                ddMut#(data#0 - 1) = makeFreeOIModuleMap(target ddMap, newTargMod, remove(ddMap.genImages, targBasisPos));

                -- Above map
                if data#0 < #ddMut - 1 then (
                    newGenImages = new MutableList;
                    ddMap = ddMut#(1 + data#0);
                    srcMod = source ddMap;
                    targMod = target ddMap;

                    if not (isZero srcMod or isZero targMod) then (
                        for i to #ddMap.genImages - 1 do (
                            if isZero ddMap.genImages#i then newGenImages#i = ddMap.genImages#i else (
                                oiTerms := getOITermsFromVector ddMap.genImages#i;
                                newTerms := for term in oiTerms list (
                                    idx := term.basisIndex.idx;
                                    if idx == srcBasisPos + 1 then continue; -- Projection
                                    if idx > srcBasisPos + 1 then idx = idx - 1; -- Relabel
                                    makeOITerm(term.ringElement, makeBasisIndex(newSrcMod, term.basisIndex.oiMap, idx))
                                );

                                newGenImages#i = getVectorFromOITerms newTerms
                            )
                        )
                    );

                    ddMut#(1 + data#0) = makeFreeOIModuleMap(newSrcMod, srcMod, new List from newGenImages)
                )
            )
        )
    );

    ret := new OIResolution from {dd => new List from ddMut, modules => new List from modulesMut};

    -- Store the resolution
    oiResCache#(L, n, opts.FastNonminimal, opts.MinimalOIGB) = ret;

    ret
)

-- Verify that an OIResolution is a complex
isComplex = method(TypicalValue => Boolean)
isComplex OIResolution := C -> (
    if #C.dd < 2 then error "expected a sequence with at least two maps";

    -- Check if the maps compose to zero
    for i from 1 to #C.dd - 1 do (
        modMap0 := C.dd#(i - 1);
        modMap1 := C.dd#i;
        if isZero modMap0 or isZero modMap1 then continue;
        srcMod := source modMap1;
        basisElts := for i to #srcMod.genWidths - 1 list makeBasisElement makeBasisIndex(srcMod, makeOIMap(srcMod.genWidths#i, toList(1..srcMod.genWidths#i)), i + 1);
        for basisElt in basisElts do (
            result := modMap0 modMap1 getVectorFromOITerms {basisElt};
            if not isZero result then return false
        )
    );

    true
)