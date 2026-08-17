import { NgFor, NgIf } from '@angular/common';
import { Component, OnInit } from '@angular/core';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { DocumentRecord, DocumentsService } from '../../services/documents.service';

@Component({
  selector: 'app-upload-documents',
  standalone: true,
  imports: [NgFor, NgIf, RouterLink],
  template: `
    <div class="page">
      <div class="page-header">
        <h1>Upload your documents</h1>
        <p class="page-subtitle">
          Upload all three required documents. Once all three are in, our fraud/forensics check kicks off automatically in the background.
        </p>
      </div>

      <div class="upload-doc-row" *ngFor="let type of requiredTypes">
        <label>{{ type }}<input type="file" (change)="onFileSelected($event, type)" [disabled]="uploading" /></label>
      </div>

      <h3>Uploaded so far</h3>
      <ul class="upload-list" *ngIf="uploadedDocuments.length">
        <li class="upload-item" *ngFor="let doc of uploadedDocuments">
          <span class="upload-item-name">{{ doc.type }}</span>
          <span class="status-badge">{{ doc.status }}</span>
        </li>
      </ul>
      <p *ngIf="!uploadedDocuments.length" style="margin-top: 0">No documents uploaded yet.</p>

      <a class="btn-link" [routerLink]="['/applications', applicationId, 'status']">Continue to status tracking →</a>
    </div>
  `,
})
export class UploadDocumentsComponent implements OnInit {
  applicationId = '';
  requiredTypes = ['IdentityProof', 'IncomeProof', 'BankStatement'];
  uploadedDocuments: DocumentRecord[] = [];
  uploading = false;

  constructor(
    private readonly route: ActivatedRoute,
    private readonly documents: DocumentsService,
  ) {}

  ngOnInit(): void {
    this.applicationId = this.route.snapshot.paramMap.get('id') ?? '';
    this.refresh();
  }

  onFileSelected(event: Event, type: string): void {
    const input = event.target as HTMLInputElement;
    const file = input.files?.[0];
    if (!file) return;

    this.uploading = true;
    this.documents.uploadDocument(this.applicationId, type, file).subscribe({
      next: () => {
        this.uploading = false;
        this.refresh();
      },
      error: (err) => {
        this.uploading = false;
        console.error(err);
      },
    });
  }

  private refresh(): void {
    this.documents.getDocumentsForApplication(this.applicationId).subscribe((docs) => (this.uploadedDocuments = docs));
  }
}
