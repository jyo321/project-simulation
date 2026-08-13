import { HttpClient } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';
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

@Injectable({ providedIn: 'root' })
export class DocumentsService {
  private readonly baseUrl = environment.documentsApiBaseUrl;

  constructor(private readonly http: HttpClient) {}

  getDocumentsForApplication(loanApplicationId: string): Observable<DocumentRecord[]> {
    return this.http.get<DocumentRecord[]>(`${this.baseUrl}/documents/by-application/${loanApplicationId}`);
  }

  getDownloadUrl(documentId: string): Observable<{ downloadUrl: string }> {
    return this.http.get<{ downloadUrl: string }>(`${this.baseUrl}/documents/${documentId}/download-url`);
  }
}
