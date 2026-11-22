import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { initializeApp } from "firebase/app";
import { getFunctions, httpsCallable } from "firebase/functions";
import config from "./firebase-config.generated.json";
import { CheckIn } from "./check-in.jsx";
import "./style.css";
if (config.projectId !== "rally4ever-3adaf")
  throw Error("Unexpected Firebase project");
const app = initializeApp(config),
  functions = getFunctions(app, "australia-southeast1");
const call = async (name, data) =>
  (await httpsCallable(functions, name)(data)).data;
// Preserve default Firebase handling for password resets/email verification.
// Only EMAIL_SIGNIN is handled by this guest page; no app Auth session is created.
const mode = new URL(location.href).searchParams.get("mode");
if (mode && mode !== "signIn") {
  const known = [
    "resetPassword",
    "verifyEmail",
    "recoverEmail",
    "verifyAndChangeEmail",
    "revertSecondFactorAddition",
  ];
  if (known.includes(mode)) {
    location.replace(
      "https://rally4ever-3adaf.firebaseapp.com/__/auth/action" +
        location.search,
    );
  } else
    document.getElementById("root").textContent =
      "This email action is not supported. Request a new link.";
} else
  createRoot(document.getElementById("root")).render(<CheckIn call={call} />);
