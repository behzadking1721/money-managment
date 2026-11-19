//+------------------------------------------------------------------+
//|                                           RecoveryEngine.mqh     |
//|  Persistence & Recovery Engine (Phase 12 / TD-05, TD-17):       |
//|  Orchestrates restart recovery on top of CStateStore.           |
//|  Reuses: StateStore (persistence), Protection (limits),          |
//|  TradeLifecycle (events), Statistics (open risk).                |
//|  Safety rules:                                                  |
//|   - Never auto-reset / re-base protective baselines when       |
//|     continuity is uncertain.                                   |
//|   - Risk-increasing actions blocked until explicit resolution. |
//|   - Risk-reducing position management (BE / trail / close)     |
//|     stays active even when recovery is blocked/failed.         |
//|   - Original state + .bak preserved; no auto overwrite.        |
//|   - No account identity (login/broker/server) persisted.       |
//+------------------------------------------------------------------+
#ifndef MM_RECOVERY_ENGINE_MQH
#define MM_RECOVERY_ENGINE_MQH

#include "../State/StateStore.mqh"
#include "../Core/Contracts.mqh"
#include "../Core/Logger.mqh"

enum ENUM_MM_RECOVERY_OUTCOME
{
   MM_RECOVERY_OUTCOME_NONE        = 0,
   MM_RECOVERY_OUTCOME_PRIMARY_OK,      // state loaded from primary; continuity uncertain => blocked pending resolution
   MM_RECOVERY_OUTCOME_BACKUP_FALLBACK, // primary corrupt; backup loaded; continuity uncertain => blocked pending resolution
   MM_RECOVERY_OUTCOME_DEGRADED,        // loaded but degraded
   MM_RECOVERY_OUTCOME_BLOCKED,         // no valid state artifact; manual review required; no rebase
   MM_RECOVERY_OUTCOME_EXPLICIT_INIT_OK // explicit new protective state initialized from current MT5 values
};

struct MM_RecoveryReport
{
   ENUM_MM_RECOVERY_OUTCOME outcome;
   bool operational;                     // true only when store operational + explicit continuity
   bool riskIncreasingBlocked;           // true when new risk-increasing entries must be rejected
   bool riskReductionActive;             // ALWAYS true: position risk reduction remains active
   bool manualReviewRequired;
   bool explicitResolutionRequired;
   string reason;
   ENUM_MM_STORE_RESULT storeResult;
   ENUM_MM_STORE_RECOVERY storeRecovery;
   void Reset()
   {
      outcome=MM_RECOVERY_OUTCOME_NONE;
      operational=false;
      riskIncreasingBlocked=true;
      riskReductionActive=true;
      manualReviewRequired=false;
      explicitResolutionRequired=false;
      reason="";
      storeResult=MM_STORE_OK;
      storeRecovery=MM_RECOVERY_NONE;
   }
};

class CRecoveryEngine
{
private:
   CStateStore     *m_store;
   MM_RecoveryReport m_report;

public:
   CRecoveryEngine(){ m_store=NULL; m_report.Reset(); }

   void SetStore(CStateStore &store){ m_store=GetPointer(store); }

   // Call once on EA init/restart, after StateStore.Init().
   // Evaluates persisted state and produces a recovery report.
   // Never auto-initializes or re-bases protective state.
   bool RecoverOnRestart()
   {
      m_report.Reset();
      if(m_store==NULL)
      {
         m_report.reason="store_not_set";
         m_report.riskReductionActive=true;
         g_mmLog.Error("RECOVERY_SETUP","state store not bound to recovery engine");
         return false;
      }

      bool operational = m_store.IsOperational();
      ENUM_MM_STORE_RESULT res = m_store.LastResult();
      ENUM_MM_STORE_RECOVERY rec = m_store.LastRecovery();
      string reason = m_store.StatusReason();

      m_report.storeResult = res;
      m_report.storeRecovery = rec;
      m_report.reason = reason;
      m_report.riskReductionActive = true; // invariant: position risk reduction stays active

      if(operational)
      {
         m_report.operational = true;
         m_report.riskIncreasingBlocked = false;
         m_report.outcome = MM_RECOVERY_OUTCOME_PRIMARY_OK;
         m_report.explicitResolutionRequired = false;
         m_report.manualReviewRequired = false;
         g_mmLog.Info("RECOVERY_PRIMARY_OK","state operational; risk-increasing allowed");
      }
      else
      {
         m_report.operational = false;
         m_report.riskIncreasingBlocked = true;
         m_report.explicitResolutionRequired = m_store.RequiresExplicitResolution();
         m_report.manualReviewRequired = m_store.RequiresManualReview();

         // Classify recovery path without mutating persisted files.
         if(rec == MM_RECOVERY_BACKUP)
         {
            m_report.outcome = MM_RECOVERY_OUTCOME_BACKUP_FALLBACK;
            m_report.reason = "primary_invalid_backup_restored_continuity_uncertain";
            g_mmLog.Warn("RECOVERY_BACKUP_FALLBACK","primary invalid; backup loaded; continuity uncertain; risk-increasing blocked");
         }
         else if(res == MM_STORE_ERR_SCHEMA_FUTURE)
         {
            m_report.outcome = MM_RECOVERY_OUTCOME_BLOCKED;
            m_report.reason = "schema_future_blocked_no_rebase";
            g_mmLog.Error("RECOVERY_BLOCKED","future schema; blocked; no auto rebase");
         }
         else if(res == MM_STORE_ERR_RECOVERY_FAILED || !m_store.HasRestoredProtectiveState())
         {
            m_report.outcome = MM_RECOVERY_OUTCOME_BLOCKED;
            m_report.reason = "no_valid_state_manual_review_required";
            g_mmLog.Error("RECOVERY_BLOCKED","no valid state artifact; blocked pending explicit resolution; no rebase");
         }
         else
         {
            // state loaded but continuity unproven (primary OK or legacy migrated)
            m_report.outcome = MM_RECOVERY_OUTCOME_PRIMARY_OK;
            m_report.reason = "continuity_uncertain_explicit_resolution_required";
            g_mmLog.Warn("RECOVERY_CONTINUITY_UNCERTAIN","state loaded but continuity unproven; risk-increasing blocked");
         }
      }
      return m_report.operational;
   }

   // Explicit user-confirmed path: initialize NEW protective state from current MT5 runtime values.
   // Preserves previous persisted evidence in StateStore before replacement.
   bool ExplicitNewProtectiveInit(double dayStartBalance, double dayStartEquity, double peakEquity, double peakBalance,
                                  ENUM_MM_ACCOUNT_MODE mode, const string activeProfileId)
   {
      if(m_store==NULL) return false;
      bool ok = m_store.InitializeNewProtectiveStateFromCurrent(dayStartBalance, dayStartEquity, peakEquity, peakBalance,
                                                                mode, activeProfileId, true);
      if(ok)
      {
         m_report.Reset();
         m_report.operational = true;
         m_report.riskIncreasingBlocked = false;
         m_report.riskReductionActive = true;
         m_report.outcome = MM_RECOVERY_OUTCOME_EXPLICIT_INIT_OK;
         m_report.reason = "explicit_new_protective_state_initialized";
         g_mmLog.Info("RECOVERY_EXPLICIT_INIT_OK","new protective state initialized from current MT5 values");
      }
      else
      {
         m_report.riskIncreasingBlocked = true;
         m_report.riskReductionActive = true;
         m_report.outcome = MM_RECOVERY_OUTCOME_BLOCKED;
         m_report.reason = "explicit_init_failed";
         g_mmLog.Error("RECOVERY_EXPLICIT_INIT_FAIL", m_store.StatusReason());
      }
      return ok;
   }

   bool IsOperational(){ return m_report.operational; }
   bool RiskIncreasingBlocked(){ return m_report.riskIncreasingBlocked; }
   bool RiskReductionActive(){ return m_report.riskReductionActive; } // invariant: always true
   bool RequiresExplicitResolution(){ return m_report.explicitResolutionRequired; }
   bool RequiresManualReview(){ return m_report.manualReviewRequired; }
   ENUM_MM_RECOVERY_OUTCOME Outcome(){ return m_report.outcome; }
   string Reason(){ return m_report.reason; }
   string ReportText()
   {
      return "outcome="+(string)m_report.outcome+
             " operational="+(m_report.operational?"1":"0")+
             " riskIncBlocked="+(m_report.riskIncreasingBlocked?"1":"0")+
             " riskReductionActive="+(m_report.riskReductionActive?"1":"0")+
             " reason="+m_report.reason;
   }
};

#endif // MM_RECOVERY_ENGINE_MQH
