# app/routers/print_jobs.py
#
# Two audiences:
#   • Flutter app  — creates jobs, checks status        (API_TOKEN)
#   • Print agent  — polls for pending, marks done/fail (PRINT_AGENT_TOKEN)

from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Response, status
from app.auth import require_auth, require_agent_auth
from app.database import get_pool
from app.models import PrintJob, PrintJobCreate, PrintJobStatusUpdate

router = APIRouter(prefix="/print-jobs", tags=["print"])


@router.post("/", response_model=PrintJob, status_code=status.HTTP_201_CREATED)
async def create_print_job(
    body: PrintJobCreate,
    *,
    _: None = Depends(require_auth),
):
    """Flutter app enqueues a print job. PDF is generated async (see pdf.py)."""
    pool = get_pool()
    row = await pool.fetchrow(
        """
        INSERT INTO print_jobs (job_type, params)
        VALUES ($1, $2)
        RETURNING id, job_type, params, status, attempts, error,
                  created_at, updated_at, printed_at
        """,
        body.job_type, body.params,
    )
    return dict(row)


@router.get("/", response_model=list[PrintJob])
async def list_print_jobs(
    status_filter: str | None = None,
    *,
    _: None = Depends(require_auth),
):
    pool = get_pool()
    if status_filter:
        rows = await pool.fetch(
            """
            SELECT id, job_type, params, status, attempts, error,
                   created_at, updated_at, printed_at
            FROM print_jobs WHERE status = $1 ORDER BY created_at DESC
            """,
            status_filter,
        )
    else:
        rows = await pool.fetch(
            """
            SELECT id, job_type, params, status, attempts, error,
                   created_at, updated_at, printed_at
            FROM print_jobs ORDER BY created_at DESC LIMIT 50
            """
        )
    return [dict(r) for r in rows]


# ─── Print-agent endpoints ────────────────────────────────────────────────────

@router.get("/pending", response_model=list[PrintJob])
async def get_pending_jobs(
    _: None = Depends(require_agent_auth),
):
    """Agent polls this. Returns jobs that are pending and not yet claimed."""
    pool = get_pool()
    rows = await pool.fetch(
        """
        SELECT id, job_type, params, status, attempts, error,
               created_at, updated_at, printed_at
        FROM print_jobs
        WHERE status = 'pending'
        ORDER BY created_at ASC
        LIMIT 5
        """
    )
    return [dict(r) for r in rows]


@router.get("/{job_id}/pdf")
async def download_pdf(
    job_id: UUID,
    *,
    _: None = Depends(require_agent_auth),
):
    """Agent downloads the rendered PDF bytes for a job."""
    pool = get_pool()
    row = await pool.fetchrow(
        "SELECT pdf FROM print_jobs WHERE id = $1", job_id
    )
    if not row or not row["pdf"]:
        raise HTTPException(status_code=404, detail="PDF not ready")
    return Response(content=bytes(row["pdf"]), media_type="application/pdf")


@router.patch("/{job_id}/status", response_model=PrintJob)
async def update_job_status(
    job_id: UUID,
    body: PrintJobStatusUpdate,
    *,
    _: None = Depends(require_agent_auth),
):
    """Agent reports success or failure after attempting to print."""
    if body.status not in ("printing", "done", "failed"):
        raise HTTPException(status_code=400, detail="status must be printing, done, or failed")

    pool = get_pool()
    row = await pool.fetchrow(
        """
        UPDATE print_jobs
        SET status     = $2,
            error      = $3,
            attempts   = attempts + 1,
            printed_at = CASE WHEN $2 = 'done' THEN now() ELSE printed_at END
        WHERE id = $1
        RETURNING id, job_type, params, status, attempts, error,
                  created_at, updated_at, printed_at
        """,
        job_id, body.status, body.error,
    )
    if not row:
        raise HTTPException(status_code=404, detail="Job not found")
    return dict(row)