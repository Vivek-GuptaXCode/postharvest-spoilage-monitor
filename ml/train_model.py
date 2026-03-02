import os
import pickle
import numpy as np
import pandas as pd
import xgboost as xgb
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sklearn.model_selection import train_test_split, StratifiedKFold, cross_val_score
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import (
    classification_report,
    confusion_matrix,
    ConfusionMatrixDisplay,
    mean_absolute_error,
    r2_score,
    accuracy_score,
)

# Resolve paths relative to this script
_DIR = os.path.dirname(os.path.abspath(__file__))

df = pd.read_csv(os.path.join(_DIR, "data", "synthetic_sensor_data.csv"))
print(f"Loaded {len(df):,} rows  |  Columns: {list(df.columns)}")
print(f"\nClass distribution:")
print(df["risk_level"].value_counts().to_string())


le_commodity = LabelEncoder()
df["commodity_encoded"] = le_commodity.fit_transform(df["commodity_type"])

# Vapor Pressure Deficit (Magnus formula)
svp = 0.6108 * np.exp(17.27 * df["temperature"] / (df["temperature"] + 237.3))
avp = svp * (df["humidity"] / 100)
df["vpd"] = svp - avp

# Commodity-specific optimal midpoints
OPTIMAL_TEMP_MID = {
    "tomato": 13.5, "potato": 4.5, "banana": 13.5,
    "rice": 17.5, "onion": 1.0,
}
OPTIMAL_RH_MID = {
    "tomato": 90.0, "potato": 96.5, "banana": 92.5,
    "rice": 57.5, "onion": 67.5,
}

df["temp_deviation"]     = abs(df["temperature"] - df["commodity_type"].map(OPTIMAL_TEMP_MID))
df["humidity_deviation"]  = abs(df["humidity"]    - df["commodity_type"].map(OPTIMAL_RH_MID))
df["temp_hours_stress"]   = df["temp_deviation"] * df["hours_in_storage"]

FEATURE_COLS = [
    "temperature", "humidity", "co2", "gas_level",
    "hours_in_storage", "commodity_encoded", "vpd",
    "temp_deviation", "humidity_deviation", "temp_hours_stress",
]

X = df[FEATURE_COLS].values
y_score = df["risk_score"].values          # continuous 0-100
y_days  = df["days_to_spoilage"].values     # continuous ≥ 0

# Also encode risk_level for comparison metrics
le_risk = LabelEncoder()
le_risk.fit(["low", "medium", "high", "critical"])
y_class = le_risk.transform(df["risk_level"])

def score_to_level(scores):
    """Bin continuous risk scores into categorical risk levels."""
    levels = np.where(
        scores <= 25, "low",
        np.where(scores <= 50, "medium",
                 np.where(scores <= 75, "high", "critical"))
    )
    return levels

print(f"\nFeatures ({len(FEATURE_COLS)}): {FEATURE_COLS}")


(
    X_train, X_test,
    ys_train, ys_test,     # risk_score
    yd_train, yd_test,     # days_to_spoilage
    yc_train, yc_test,     # risk_level (encoded)
) = train_test_split(
    X, y_score, y_days, y_class,
    test_size=0.2, random_state=42, stratify=y_class,
)
print(f"\nTrain: {len(X_train):,}  |  Test: {len(X_test):,}")


print("\n" + "=" * 60)
print("APPROACH A: Two-Stage (Risk-Score Regressor → Bin)")
print("=" * 60)

score_reg = xgb.XGBRegressor(
    n_estimators=800,
    max_depth=8,
    learning_rate=0.1,
    subsample=0.8,
    colsample_bytree=0.8,
    min_child_weight=3,
    gamma=0.1,
    reg_alpha=0.05,
    reg_lambda=1.0,
    objective="reg:squarederror",
    eval_metric="mae",
    early_stopping_rounds=30,
    random_state=42,
    n_jobs=-1,
)
score_reg.fit(X_train, ys_train, eval_set=[(X_test, ys_test)], verbose=100)
print(f"Best iteration (score regressor): {score_reg.best_iteration}")

# Predict risk_score, then bin for classification
ys_pred = np.clip(score_reg.predict(X_test), 0, 100)
print(f"\nRisk-Score Regression:")
print(f"  MAE:  {mean_absolute_error(ys_test, ys_pred):.2f} pts")
print(f"  R²:   {r2_score(ys_test, ys_pred):.4f}")

# Derive risk_level from predicted score
levels_pred = score_to_level(ys_pred)
levels_true = score_to_level(ys_test)
two_stage_acc = accuracy_score(levels_true, levels_pred)

print(f"\nTwo-Stage Classification (via score binning):")
print(f"  Accuracy: {two_stage_acc:.4f}")
print(classification_report(
    levels_true, levels_pred,
    target_names=["critical", "high", "low", "medium"],
))


print("\n" + "=" * 60)
print("APPROACH B: Direct XGBoost Classifier")
print("=" * 60)

direct_clf = xgb.XGBClassifier(
    n_estimators=800,
    max_depth=8,
    learning_rate=0.1,
    subsample=0.8,
    colsample_bytree=0.8,
    min_child_weight=3,
    gamma=0.1,
    reg_alpha=0.05,
    reg_lambda=1.0,
    objective="multi:softprob",
    eval_metric="mlogloss",
    early_stopping_rounds=30,
    random_state=42,
    n_jobs=-1,
)
direct_clf.fit(X_train, yc_train, eval_set=[(X_test, yc_test)], verbose=100)

yc_pred_direct = direct_clf.predict(X_test)
direct_acc = accuracy_score(yc_test, yc_pred_direct)
print(f"\nDirect Classifier Accuracy: {direct_acc:.4f}")
print(classification_report(
    yc_test, yc_pred_direct,
    target_names=le_risk.classes_,
))


try:
    import lightgbm as lgb
    print("\n" + "=" * 60)
    print("APPROACH C: LightGBM Classifier")
    print("=" * 60)

    lgb_clf = lgb.LGBMClassifier(
        n_estimators=800,
        max_depth=8,
        learning_rate=0.1,
        subsample=0.8,
        colsample_bytree=0.8,
        min_child_weight=3,
        reg_alpha=0.05,
        reg_lambda=1.0,
        num_class=4,
        objective="multiclass",
        random_state=42,
        n_jobs=-1,
        verbose=-1,
    )
    lgb_clf.fit(
        X_train, yc_train,
        eval_set=[(X_test, yc_test)],
        callbacks=[lgb.early_stopping(30), lgb.log_evaluation(100)],
    )
    yc_pred_lgb = lgb_clf.predict(X_test)
    lgb_acc = accuracy_score(yc_test, yc_pred_lgb)
    print(f"\nLightGBM Accuracy: {lgb_acc:.4f}")
    print(classification_report(
        yc_test, yc_pred_lgb,
        target_names=le_risk.classes_,
    ))
    HAS_LGB = True
except ImportError:
    print("\n[INFO] LightGBM not installed — skipping comparison.")
    print("       Install with: pip install lightgbm")
    lgb_acc = 0.0
    HAS_LGB = False


print("\n" + "=" * 60)
print("MODEL COMPARISON")
print("=" * 60)
print(f"  Two-Stage (score reg → bin) : {two_stage_acc:.4f}")
print(f"  Direct XGBoost Classifier   : {direct_acc:.4f}")
if HAS_LGB:
    print(f"  LightGBM Classifier         : {lgb_acc:.4f}")
print(f"\n  >>> WINNER: {'Two-Stage' if two_stage_acc >= direct_acc else 'Direct XGBoost'}")

# 5-fold CV on the winner for judge-ready reporting
print("\nRunning 5-fold CV on two-stage approach...")
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
cv_accs = []
for fold, (train_idx, val_idx) in enumerate(cv.split(X, y_class)):
    fold_reg = xgb.XGBRegressor(
        n_estimators=min(score_reg.best_iteration + 1, 800),
        max_depth=8, learning_rate=0.1,
        subsample=0.8, colsample_bytree=0.8,
        min_child_weight=3, gamma=0.1,
        reg_alpha=0.05, reg_lambda=1.0,
        objective="reg:squarederror",
        random_state=42, n_jobs=-1,
    )
    fold_reg.fit(X[train_idx], y_score[train_idx])
    fold_pred = np.clip(fold_reg.predict(X[val_idx]), 0, 100)
    fold_acc = accuracy_score(score_to_level(y_score[val_idx]),
                              score_to_level(fold_pred))
    cv_accs.append(fold_acc)
cv_accs = np.array(cv_accs)
print(f"5-Fold CV Accuracy (two-stage): {cv_accs.mean():.4f} ± {cv_accs.std():.4f}")
print(f"Fold scores: {[round(s, 4) for s in cv_accs]}")

# Confusion matrix for the two-stage approach
cm = confusion_matrix(levels_true, levels_pred, labels=["low", "medium", "high", "critical"])
disp = ConfusionMatrixDisplay(cm, display_labels=["low", "medium", "high", "critical"])
disp.plot(cmap="Blues")
plt.title("Spoilage Risk — Confusion Matrix (Two-Stage)")
plt.tight_layout()
plt.savefig(os.path.join(_DIR, "plots", "confusion_matrix.png"), dpi=150)
print("Saved plots/confusion_matrix.png")


print("\n" + "=" * 60)
print("DAYS-TO-SPOILAGE REGRESSOR")
print("=" * 60)

days_reg = xgb.XGBRegressor(
    n_estimators=800,
    max_depth=8,
    learning_rate=0.1,
    subsample=0.8,
    colsample_bytree=0.8,
    objective="reg:squarederror",
    eval_metric="mae",
    early_stopping_rounds=30,
    random_state=42,
    n_jobs=-1,
)
days_reg.fit(X_train, yd_train, eval_set=[(X_test, yd_test)], verbose=100)
print(f"Best iteration (days regressor): {days_reg.best_iteration}")

yd_pred = days_reg.predict(X_test)
print(f"\n  MAE:  {mean_absolute_error(yd_test, yd_pred):.2f} days")
print(f"  R²:   {r2_score(yd_test, yd_pred):.4f}")


fig, axes = plt.subplots(1, 2, figsize=(16, 6))
xgb.plot_importance(score_reg, ax=axes[0], max_num_features=10, importance_type="gain")
axes[0].set_title("Risk-Score Model — Feature Importance (Gain)")
xgb.plot_importance(days_reg, ax=axes[1], max_num_features=10, importance_type="gain")
axes[1].set_title("Days-to-Spoilage — Feature Importance (Gain)")
plt.tight_layout()
plt.savefig(os.path.join(_DIR, "plots", "feature_importance.png"), dpi=150)
print("Saved plots/feature_importance.png")


with open(os.path.join(_DIR, "risk_score_model.pkl"), "wb") as f:
    pickle.dump(score_reg, f)
with open(os.path.join(_DIR, "spoilage_regressor.pkl"), "wb") as f:
    pickle.dump(days_reg, f)
with open(os.path.join(_DIR, "model_metadata.pkl"), "wb") as f:
    pickle.dump({
        "label_encoders": {"commodity": le_commodity},
        "feature_names": FEATURE_COLS,
        "risk_labels": ["low", "medium", "high", "critical"],
        "model_version": "4.0",
        "approach": "two-stage (score regressor → bin)",
        "best_iteration_score": score_reg.best_iteration,
        "best_iteration_days": days_reg.best_iteration,
        "cv_accuracy_mean": round(float(cv_accs.mean()), 4),
        "cv_accuracy_std": round(float(cv_accs.std()), 4),
        "optimal_temp_mid": OPTIMAL_TEMP_MID,
        "optimal_rh_mid": OPTIMAL_RH_MID,
    }, f)

for name in ["risk_score_model.pkl", "spoilage_regressor.pkl", "model_metadata.pkl"]:
    fpath = os.path.join(_DIR, name)
    print(f"{name}: {os.path.getsize(fpath) / 1024:.1f} KB")

print("\nAll artefacts saved. Copy *.pkl + model_metadata.pkl to cloud-functions/predict/ before deploying.")