import { HttpClient } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
import { switchMap } from 'rxjs/operators';
import { environment } from '../../environments/environment';

export interface DocumentRecord {
  id: string;
  loanApplicationId: string;
  type: string;
  status: string;
  fileName: string;
  uploadedAt: string;
  validatedAt: string | null;
}

interface CreateUploadUrlResponse {
  documentId: string;
  uploadUrl: string;
  bucket: string;
  objectKey: string;
}

@Injectable({ providedIn: 'root' })
export class DocumentsService {
  private readonly baseUrl = environment.documentsApiBaseUrl;

  constructor(private readonly http: HttpClient) {}

  /**
   * Full upload flow: ask Documents.Api for a pre-signed S3 PUT URL, upload the file bytes
   * straight to S3 from the browser (never through our API), then confirm — which is what
   * triggers the service-triggered Document Validation Worker (and, once every required
   * document type is present, the fire-and-forget Fraud/Forensics job) server-side.
   */
  uploadDocument(loanApplicationId: string, type: string, file: File): Observable<unknown> {
    return this.http
      .post<CreateUploadUrlResponse>(`${this.baseUrl}/documents/upload-url`, {
        loanApplicationId,
        type,
        fileName: file.name,
        contentType: file.type || 'application/octet-stream',
      })
      .pipe(
        switchMap((created) =>
          this.http.put(created.uploadUrl, file, { headers: { 'Content-Type': file.type || 'application/octet-stream' } }).pipe(
            switchMap(() => this.http.post(`${this.baseUrl}/documents/${created.documentId}/confirm-upload`, {})),
          ),
        ),
      );
  }

  getDocumentsForApplication(loanApplicationId: string): Observable<DocumentRecord[]> {
    return this.http.get<DocumentRecord[]>(`${this.baseUrl}/documents/by-application/${loanApplicationId}`);
  }
}
