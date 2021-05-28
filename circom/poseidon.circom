include "../node_modules/circomlib/circuits/poseidon_constants.circom";
include "../node_modules/circomlib/circuits/bitify.circom";
include "../node_modules/circomlib/circuits/escalarmulany.circom";

// The S-box function. For BN254, it is (in ^ 5)
template Sigma() {
    signal input in;
    signal output out;

    signal in2;
    signal in4;

    in2 <== in*in;
    in4 <== in2*in2;

    out <== in4*in;
}

// The AddRoundConstants function.
template Ark(t, C, r) {
    signal input in[t];
    signal output out[t];

    for (var i=0; i<t; i++) {
        out[i] <== in[i] + C[i + r];
    }
}

// The MixLayer function.
template Mix(t, M) {
    signal input in[t];
    signal output out[t];

    var lc;
    for (var i=0; i<t; i++) {
        lc = 0;
        for (var j=0; j<t; j++) {
            lc += M[i][j]*in[j];
        }
        out[i] <== lc;
    }
}

template Poseidon(nInputs) {
    signal input inputs[nInputs];
    signal output out;

    component strategy = PoseidonStrategy(nInputs);
    for (var i = 0; i < nInputs; i ++) {
        strategy.inputs[i] <== inputs[i];
    }
    out <== strategy.out[0];
}

template PoseidonStrategy(nInputs) {
    var t = nInputs + 1;

    // Using recommended parameters from whitepaper https://eprint.iacr.org/2019/458.pdf (table 2, table 8)
    // Generated by https://extgit.iaik.tugraz.at/krypto/hadeshash/-/blob/master/code/calc_round_numbers.py
    // And rounded up to nearest integer that divides by t
    var N_ROUNDS_P[8] = [56, 57, 56, 60, 60, 63, 64, 63];
    var nRoundsF = 8;
    var nRoundsP = N_ROUNDS_P[t - 2];
    var C[t*(nRoundsF + nRoundsP)] = POSEIDON_C(t);
    var M[t][t] = POSEIDON_M(t);

    signal input inputs[nInputs];
    signal output out[t];

    component ark[nRoundsF + nRoundsP];
    component sigmaF[nRoundsF][t];
    component sigmaP[nRoundsP];
    component mix[nRoundsF + nRoundsP];

    var k;

    for (var i=0; i<nRoundsF + nRoundsP; i++) {
        ark[i] = Ark(t, C, t*i);
        for (var j=0; j<t; j++) {
            if (i==0) {
                if (j>0) {
                    ark[i].in[j] <== inputs[j-1];
                } else {
                    ark[i].in[j] <== 0;
                }
            } else {
                ark[i].in[j] <== mix[i-1].out[j];
            }
        }

        if (i < nRoundsF/2 || i >= nRoundsP + nRoundsF/2) {
            k = i < nRoundsF/2 ? i : i - nRoundsP;
            mix[i] = Mix(t, M);
            for (var j=0; j<t; j++) {
                sigmaF[k][j] = Sigma();
                sigmaF[k][j].in <== ark[i].out[j];
                mix[i].in[j] <== sigmaF[k][j].out;
            }
        } else {
            k = i - nRoundsF/2;
            mix[i] = Mix(t, M);
            sigmaP[k] = Sigma();
            sigmaP[k].in <== ark[i].out[0];
            mix[i].in[0] <== sigmaP[k].out;
            for (var j=1; j<t; j++) {
                mix[i].in[j] <== ark[i].out[j];
            }
        }
    }

    // Output the final state.
    for (var i = 0; i < t; i ++) {
        out[i] <== mix[nRoundsF + nRoundsP -1].out[i];
    }
}

template PoseidonEncrypt(messageLength) {
    signal input message[messageLength];
    signal input key[2];
    signal output ciphertext[messageLength];
}


template Ecdh() {
    // Note: The private key needs to be hashed and then pruned first
    signal private input privKey;
    signal input pubKey[2];

    signal output sharedKey[2];

    component privBits = Num2Bits(253);
    privBits.in <== privKey;

    component mulFix = EscalarMulAny(253);
    mulFix.p[0] <== pubKey[0];
    mulFix.p[1] <== pubKey[1];

    for (var i = 0; i < 253; i++) {
        mulFix.e[i] <== privBits.out[i];
    }

    sharedKey[0] <== mulFix.out[0];
    sharedKey[1] <== mulFix.out[1];
}